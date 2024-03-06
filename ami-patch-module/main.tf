data "archive_file" "lambda_zip" {
  type             = "zip"
  source_file      = "${path.module}/ami.py"
  output_file_mode = "0444"
  output_path      = "${path.module}/ami.py.zip"
}

resource "aws_cloudwatch_event_rule" "ami_lambda_schedule" {
  name                = "ami-patch-schedule"
  description         = "A schedule for the EKS AMI nodegroup patch upgrades"
  schedule_expression = var.rate
}

resource "aws_cloudwatch_event_target" "ami_lambda_schedule_target" {
  rule      = aws_cloudwatch_event_rule.ami_lambda_schedule.name
  target_id = "LambdaSchedule"
  arn       = aws_lambda_function.eks_ami_upgrade.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.eks_ami_upgrade.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ami_lambda_schedule.arn
}

resource "aws_lambda_function" "eks_ami_upgrade" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "update_node_group_function"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "ami.handler"
  runtime          = "python3.8"
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)

  environment {
    variables = {
      cluster = var.cluster
      region  = var.region
      webhook_url = var.webhook_url
    }
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "lambda_policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action   = "*",
          Effect   = "Allow",
          Resource = "*"
        }
      ]
    })
  }
}
