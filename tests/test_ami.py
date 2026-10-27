import io
import json
import os
import unittest
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError, URLError
from zipfile import ZipFile

import boto3
from botocore.exceptions import ClientError, EndpointConnectionError
from botocore.stub import Stubber

import ami


class HandlerTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(
            os.environ, {"cluster": "test", "region": "us-east-2"}, clear=True
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.client = boto3.client(
            "eks",
            region_name="us-east-2",
            aws_access_key_id="testing",
            aws_secret_access_key="testing",
        )
        self.factory = patch.object(
            ami.boto3, "client", return_value=self.client
        ).start()
        self.addCleanup(patch.stopall)
        self.stub = Stubber(self.client)
        self.stub.activate()
        self.addCleanup(self.stub.deactivate)
        self.addCleanup(self.stub.assert_no_pending_responses)

    def list_page(self, names, next_token=None, token=None):
        response = {"nodegroups": names}
        params = {"clusterName": "test"}
        if next_token:
            response["nextToken"] = next_token
        if token:
            params["nextToken"] = token
        self.stub.add_response("list_nodegroups", response, params)

    def update(self, name):
        self.stub.add_response(
            "update_nodegroup_version",
            {
                "update": {"id": "update-id", "status": "InProgress"},
            },
            {"clusterName": "test", "nodegroupName": name},
        )

    def test_all_pages_and_configured_region(self):
        self.list_page(["one"], next_token="page-two")
        self.update("one")
        self.list_page(["two"], token="page-two")
        self.update("two")
        result = ami.lambda_handler({}, None)
        self.assertEqual(
            result, {"statusCode": 200, "updated": 2, "skipped": 0, "failed": 0}
        )
        self.factory.assert_called_once_with(
            "eks", region_name="us-east-2", config=ami.AWS_CONFIG
        )

    def test_empty_cluster(self):
        self.list_page([])
        self.assertEqual(ami.lambda_handler({}, None)["updated"], 0)

    def test_missing_config_raises(self):
        for name in ("cluster", "region"):
            with (
                self.subTest(name=name),
                patch.dict(os.environ, {name: " "}),
                self.assertRaises(ValueError),
            ):
                ami.lambda_handler({}, None)
        self.factory.assert_not_called()

    def test_invalid_webhook_rejected_without_exposing_url(self):
        for url in (
            "http://example.com/token",
            "https://user:secret@example.com",
            "https://",
        ):
            with self.subTest(url=url), patch.dict(os.environ, {"webhook_url": url}):
                with self.assertRaises(ValueError) as caught:
                    ami.lambda_handler({}, None)
                self.assertNotIn(url, str(caught.exception))
        self.factory.assert_not_called()

    def test_configured_webhook_key_used(self):
        self.list_page(["one"])
        self.update("one")
        with (
            patch.dict(os.environ, {"webhook_url": "https://example.com/hook"}),
            patch.object(ami, "notify") as notify,
        ):
            ami.lambda_handler({}, None)
        self.assertEqual(notify.call_args.args[0], "https://example.com/hook")
        self.assertEqual(notify.call_args.args[1]["nodegroup"], "one")

    def test_update_failure_does_not_prevent_other_groups_and_raises(self):
        self.list_page(["bad", "good"])
        self.stub.add_client_error(
            "update_nodegroup_version",
            service_error_code="AccessDeniedException",
            expected_params={"clusterName": "test", "nodegroupName": "bad"},
        )
        self.update("good")
        with self.assertRaisesRegex(RuntimeError, "1 node group"):
            ami.lambda_handler({}, None)

    def test_busy_nodegroup_skipped(self):
        self.list_page(["busy", "good"])
        self.stub.add_client_error(
            "update_nodegroup_version",
            service_error_code="ResourceInUseException",
            expected_params={"clusterName": "test", "nodegroupName": "busy"},
        )
        self.update("good")
        result = ami.lambda_handler({}, None)
        self.assertEqual(result["updated"], 1)
        self.assertEqual(result["skipped"], 1)

    def test_listing_failure_propagates(self):
        self.stub.add_client_error(
            "list_nodegroups",
            service_error_code="AccessDeniedException",
            expected_params={"clusterName": "test"},
        )
        with self.assertRaises(ClientError):
            ami.lambda_handler({}, None)

    def test_network_failure_continues_then_raises(self):
        client = MagicMock()
        client.get_paginator.return_value.paginate.return_value = [
            {"nodegroups": ["bad", "good"]}
        ]
        client.update_nodegroup_version.side_effect = [
            EndpointConnectionError(endpoint_url="https://eks.example.com"),
            {"update": {"status": "InProgress"}},
        ]
        self.factory.return_value = client
        with self.assertRaises(RuntimeError):
            ami.lambda_handler({}, None)
        self.assertEqual(client.update_nodegroup_version.call_count, 2)

    def test_scheduler_retries_use_stable_tokens_per_nodegroup(self):
        client = MagicMock()
        client.get_paginator.return_value.paginate.return_value = [
            {"nodegroups": ["one", "two"]}
        ]
        client.update_nodegroup_version.return_value = {
            "update": {"status": "InProgress"}
        }
        self.factory.return_value = client
        schedule = "arn:aws:scheduler:us-east-2:123456789012:schedule/group/daily"
        first_run = {"id": f"{schedule}:2026-10-27T03:00:00Z"}
        next_run = {"id": f"{schedule}:2026-10-28T03:00:00Z"}
        ami.lambda_handler(first_run, None)
        ami.lambda_handler(first_run, None)
        ami.lambda_handler(next_run, None)
        calls = client.update_nodegroup_version.call_args_list
        tokens = [call.kwargs["clientRequestToken"] for call in calls]
        self.assertEqual(tokens[:2], tokens[2:4])
        self.assertNotEqual(tokens[0], tokens[1])
        self.assertNotEqual(tokens[0], tokens[4])
        self.assertTrue(all(len(token) == 64 for token in tokens))


class WebhookTests(unittest.TestCase):
    def test_json_post_timeout_and_response_closed(self):
        response = MagicMock()
        response.__enter__.return_value.status = 204
        with patch.object(ami, "build_opener") as factory:
            factory.return_value.open.return_value = response
            ami.notify(
                "https://example.com/hook",
                {"time": datetime(2026, 1, 1, tzinfo=UTC)},
            )
        request = factory.return_value.open.call_args.args[0]
        self.assertEqual(request.method, "POST")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertIn("2026-01-01", json.loads(request.data)["time"])
        self.assertEqual(factory.return_value.open.call_args.kwargs["timeout"], 5)
        response.__exit__.assert_called_once()

    def test_delivery_errors_do_not_raise_or_log_url(self):
        secret = "https://example.com/secret-token"
        errors = [
            URLError(secret),
            TimeoutError(secret),
            HTTPError(secret, 503, "Unavailable", {}, io.BytesIO()),
        ]
        for error in errors:
            with (
                self.subTest(error=type(error)),
                patch.object(ami, "build_opener") as factory,
            ):
                factory.return_value.open.side_effect = error
                with self.assertLogs(ami.LOGGER, level="WARNING") as captured:
                    ami.notify(secret, {"status": "InProgress"})
                self.assertNotIn("secret-token", " ".join(captured.output))

    def test_redirects_disabled(self):
        self.assertIsNone(
            ami.NoRedirects().redirect_request(
                None, None, 302, "Found", {}, "https://elsewhere.example"
            )
        )

    def test_optional_webhook(self):
        with patch.object(ami, "build_opener") as factory:
            ami.notify("", {})
        factory.assert_not_called()

    def test_deployment_archive_contains_only_current_source(self):
        from pathlib import Path

        root = Path(__file__).resolve().parents[1]
        with ZipFile(root / "ami.zip") as archive:
            self.assertEqual(archive.namelist(), ["ami.py"])
            self.assertEqual(archive.read("ami.py"), (root / "ami.py").read_bytes())


if __name__ == "__main__":
    unittest.main()
