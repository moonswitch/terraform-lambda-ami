data "archive_file" "lambda_zip" {
  type             = "zip"
  source_file      = "${path.module}/ami-script.py"
  output_file_mode = "0666"
  output_path      = "${path.module}/ami-script.py.zip"
}

resource "aws_lambda_function" "processing_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.processing_lambda_name
  handler          = "scheulde_test.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.processing_lambda_role.arn

  runtime = "python3.8"
}

resource "aws_iam_role" "processing_lambda_role" {
  name               = var.processing_lambda_role_name
  path               = "/service-role/"
  assume_role_policy = data.aws_iam_policy_document.assume-role-policy_document.json

  inline_policy {
    name   = "test_policy"
    policy = data.aws_iam_policy_document.lambda_access.json
  }
}

data "aws_iam_policy_document" "assume-role-policy_document" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_access" {
  statement {
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = ["*"]

  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = var.schedule_name
  description         = "Schedule for Lambda Function"
  schedule_expression = var.schedule
}

resource "aws_cloudwatch_event_target" "schedule_lambda" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "processing_lambda"
  arn       = aws_lambda_function.processing_lambda.arn
}

resource "aws_lambda_permission" "allow_events_bridge_to_run_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processing_lambda.function_name
  principal     = "events.amazonaws.com"
}