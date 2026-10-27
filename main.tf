resource "aws_cloudwatch_event_rule" "ami_lambda_schedule" {
  description         = "A schedule for the EKS AMI nodegroup patch upgrades"
  name                = "ami-patch-schedule-${var.cluster}"
  schedule_expression = var.rate

  tags = local.merge_tags
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
  filename      = "${path.module}/ami.zip"
  function_name = local.function_name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "ami.lambda_handler"
  runtime       = "python3.14"
  timeout       = 300

  depends_on = [aws_iam_role_policy.eks_ami_upgrade, aws_cloudwatch_log_group.lambda]

  source_code_hash = filebase64sha256("${path.module}/ami.zip")
  environment {
    variables = merge(
      {
        cluster = var.cluster
        region  = var.region
      },
      var.webhook_url == null ? {} : { webhook_url = var.webhook_url }
    )
  }

  tags = local.merge_tags
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 30
  tags              = local.merge_tags
}

data "aws_iam_policy_document" "eks_ami_upgrade_policy" {
  statement {
    sid       = "ListClusterNodegroups"
    actions   = ["eks:ListNodegroups"]
    resources = ["${local.eks_arn_prefix}:cluster/${var.cluster}"]
  }

  statement {
    sid       = "UpdateClusterNodegroups"
    actions   = ["eks:UpdateNodegroupVersion"]
    resources = ["${local.eks_arn_prefix}:nodegroup/${var.cluster}/*/*"]
  }

  statement {
    sid       = "WriteFunctionLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "eks_ami_upgrade" {
  name   = "lambda_policy"
  role   = aws_iam_role.lambda_execution_role.id
  policy = data.aws_iam_policy_document.eks_ami_upgrade_policy.json
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role_${var.cluster}"

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

  tags = local.merge_tags
}
