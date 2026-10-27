"""Request managed node group AMI updates and optionally report them via HTTPS."""

import hashlib
import json
import logging
import os
from http.client import HTTPException
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)
AWS_CONFIG = Config(
    connect_timeout=5,
    read_timeout=15,
    retries={"mode": "standard", "total_max_attempts": 3},
)
WEBHOOK_TIMEOUT = 5


class NoRedirects(HTTPRedirectHandler):
    """Do not forward notification data to a redirected destination."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def notify(webhook_url, details):
    """Send a best-effort notification without exposing webhook credentials."""
    if not webhook_url:
        return
    try:
        request = Request(
            webhook_url,
            data=json.dumps(details, default=str).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with build_opener(NoRedirects()).open(
            request, timeout=WEBHOOK_TIMEOUT
        ) as response:
            if not 200 <= response.status < 300:
                LOGGER.warning("Webhook delivery failed: HTTP %s", response.status)
    except HTTPError as error:
        LOGGER.warning("Webhook delivery failed: HTTP %s", error.code)
        error.close()
    except URLError, OSError, ValueError, UnicodeError, HTTPException:
        # Exception text can include the URL, which may contain a secret token.
        LOGGER.warning("Webhook delivery failed: connection or URL error")


def lambda_handler(event, context):
    """Process all pages; surface AWS failures so Lambda can retry the invocation."""
    cluster = os.environ.get("cluster", "").strip()
    region = os.environ.get("region", "").strip()
    webhook_url = os.environ.get("webhook_url", "").strip()
    if not cluster or not region:
        raise ValueError("Both cluster and region environment variables are required")
    if webhook_url:
        parsed = urlsplit(webhook_url)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.username
            or parsed.password
        ):
            raise ValueError(
                "webhook_url must be an HTTPS URL without user information"
            )

    client = boto3.client("eks", region_name=region, config=AWS_CONFIG)
    result = {"updated": 0, "skipped": 0, "failed": 0}
    event_id = event.get("id") if isinstance(event, dict) else None
    try:
        pages = client.get_paginator("list_nodegroups").paginate(clusterName=cluster)
        for page in pages:
            for nodegroup in page["nodegroups"]:
                request = {"clusterName": cluster, "nodegroupName": nodegroup}
                if event_id:
                    # EventBridge retries retain their event ID. Avoid resubmitting
                    # successful requests if another group fails in this invocation.
                    request["clientRequestToken"] = hashlib.sha256(
                        json.dumps([event_id, cluster, nodegroup]).encode("utf-8")
                    ).hexdigest()
                try:
                    response = client.update_nodegroup_version(**request)
                except ClientError as error:
                    code = error.response["Error"]["Code"]
                    if code == "ResourceInUseException":
                        result["skipped"] += 1
                        LOGGER.info(
                            "Node group %s is busy; skipping this schedule", nodegroup
                        )
                        continue
                    result["failed"] += 1
                    LOGGER.error("Node group %s update failed: %s", nodegroup, code)
                    notify(
                        webhook_url,
                        {"cluster": cluster, "nodegroup": nodegroup, "error": code},
                    )
                    continue
                except BotoCoreError:
                    result["failed"] += 1
                    LOGGER.error(
                        "Node group %s update failed: AWS SDK error", nodegroup
                    )
                    notify(
                        webhook_url,
                        {
                            "cluster": cluster,
                            "nodegroup": nodegroup,
                            "error": "AWS SDK error",
                        },
                    )
                    continue
                result["updated"] += 1
                LOGGER.info(
                    "Requested update for node group %s: %s",
                    nodegroup,
                    response["update"]["status"],
                )
                notify(
                    webhook_url,
                    {
                        "cluster": cluster,
                        "nodegroup": nodegroup,
                        "update-status": response["update"]["status"],
                        "details": response["update"],
                    },
                )
    except BotoCoreError, ClientError:
        LOGGER.error("Failed to list node groups for cluster %s", cluster)
        notify(webhook_url, {"cluster": cluster, "error": "Failed to list node groups"})
        raise

    if result["failed"]:
        raise RuntimeError(
            f"Failed to request updates for {result['failed']} node group(s)"
        )
    LOGGER.info("Node group update requests completed: %s", result)
    return {"statusCode": 200, **result}
