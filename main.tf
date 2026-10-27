resource "aws_scheduler_schedule_group" "ami_patch" {
  name = "ami-patch-${var.cluster}"
  tags = local.merge_tags
}

resource "aws_scheduler_schedule" "ami_lambda_schedule" {
  name                         = "ami-patch-schedule-${var.cluster}"
  group_name                   = aws_scheduler_schedule_group.ami_patch.name
  description                  = "A schedule for the EKS AMI nodegroup patch upgrades"
  schedule_expression          = var.rate
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.eks_ami_upgrade.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn
    # Scheduled time is stable across delivery attempts; execution-id is not.
    # Keep the handler's existing `id` contract for idempotent EKS requests.
    # Keep context placeholders literal; jsonencode escapes their angle brackets.
    input = <<-JSON
      {"id":"<aws.scheduler.schedule-arn>:<aws.scheduler.scheduled-time>"}
    JSON
  }

  depends_on = [aws_iam_role_policy.scheduler_invoke]
}

resource "aws_iam_role" "scheduler_execution_role" {
  name = "ami_scheduler_role_${var.cluster}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "scheduler.amazonaws.com" }
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnEquals = {
          "aws:SourceArn" = aws_scheduler_schedule_group.ami_patch.arn
        }
      }
    }]
  })
  tags = local.merge_tags
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "invoke_ami_patch_lambda"
  role = aws_iam_role.scheduler_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.eks_ami_upgrade.arn
    }]
  })
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
