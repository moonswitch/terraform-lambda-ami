mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/lambda_execution_role_test" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-2:123456789012:function:update_node_group_function_test" }
  }
  mock_resource "aws_scheduler_schedule_group" {
    defaults = { arn = "arn:aws:scheduler:us-east-2:123456789012:schedule-group/ami-patch-test" }
  }
  mock_resource "aws_scheduler_schedule" {
    defaults = { arn = "arn:aws:scheduler:us-east-2:123456789012:schedule/ami-patch-test/ami-patch-schedule-test" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-2:123456789012:log-group:/aws/lambda/update_node_group_function_test" }
  }
}

variables {
  region  = "us-east-2"
  cluster = "test"
}

run "runtime_and_permissions" {
  command = apply

  assert {
    condition     = aws_lambda_function.eks_ami_upgrade.runtime == "python3.14"
    error_message = "Use the supported Python runtime."
  }
  assert {
    condition     = !contains(keys(aws_lambda_function.eks_ami_upgrade.environment[0].variables), "webhook_url")
    error_message = "An unset webhook must be omitted rather than passed as null."
  }
  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 30
    error_message = "Function logs must have bounded retention."
  }
  assert {
    condition = toset(flatten([
      for statement in data.aws_iam_policy_document.eks_ami_upgrade_policy.statement : tolist(statement.actions)
    ])) == toset(["eks:ListNodegroups", "eks:UpdateNodegroupVersion", "logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "Grant only the four actions used by the Lambda."
  }
  assert {
    condition = one([
      for statement in data.aws_iam_policy_document.eks_ami_upgrade_policy.statement : statement.resources
      if statement.sid == "ListClusterNodegroups"
    ]) == toset(["arn:aws:eks:us-east-2:123456789012:cluster/test"])
    error_message = "Listing must be scoped to this cluster."
  }
  assert {
    condition = one([
      for statement in data.aws_iam_policy_document.eks_ami_upgrade_policy.statement : statement.resources
      if statement.sid == "WriteFunctionLogs"
    ]) == toset(["arn:aws:logs:us-east-2:123456789012:log-group:/aws/lambda/update_node_group_function_test:log-stream:*"])
    error_message = "Logs must be scoped to this function's log streams."
  }
  assert {
    condition = one([
      for statement in data.aws_iam_policy_document.eks_ami_upgrade_policy.statement : statement.resources
      if statement.sid == "UpdateClusterNodegroups"
    ]) == toset(["arn:aws:eks:us-east-2:123456789012:nodegroup/test/*/*"])
    error_message = "Updates must be scoped to this cluster's node groups."
  }
}

run "webhook_environment" {
  command = plan
  variables {
    webhook_url = "https://example.com/webhook"
  }
  assert {
    condition     = aws_lambda_function.eks_ami_upgrade.environment[0].variables["webhook_url"] == var.webhook_url
    error_message = "The configured webhook must use the handler's environment key."
  }
}

run "reject_insecure_webhook" {
  command = plan
  variables {
    webhook_url = "http://example.com/webhook"
  }
  expect_failures = [var.webhook_url]
}

run "scheduler_defaults_and_permissions" {
  command = apply

  assert {
    condition     = output.schedule_expression == "cron(0 3 * * ? *)" && output.schedule_timezone == "UTC"
    error_message = "The default must run at 3 a.m. daily in UTC."
  }
  assert {
    condition     = aws_scheduler_schedule.ami_lambda_schedule.flexible_time_window[0].mode == "OFF"
    error_message = "Do not spread daily invocations across a flexible time window."
  }
  assert {
    condition     = output.schedule_arn == aws_scheduler_schedule.ami_lambda_schedule.arn
    error_message = "Expose the Scheduler ARN to callers."
  }
  assert {
    condition     = aws_scheduler_schedule_group.ami_patch.tags["managedByIAC"] == "Yes"
    error_message = "Preserve schedule tags on the schedule group."
  }
  assert {
    condition     = jsondecode(aws_scheduler_schedule.ami_lambda_schedule.target[0].input).id == "<aws.scheduler.schedule-arn>:<aws.scheduler.scheduled-time>" && strcontains(aws_scheduler_schedule.ami_lambda_schedule.target[0].input, "<aws.scheduler.scheduled-time>")
    error_message = "Retries must use a stable schedule/time event ID."
  }
  assert {
    condition     = aws_scheduler_schedule.ami_lambda_schedule.target[0].arn == aws_lambda_function.eks_ami_upgrade.arn && aws_scheduler_schedule.ami_lambda_schedule.target[0].role_arn == aws_iam_role.scheduler_execution_role.arn
    error_message = "Scheduler must target this Lambda through the execution role."
  }
  assert {
    condition = (
      length(data.aws_iam_policy_document.scheduler_invoke.statement) == 1 &&
      one(data.aws_iam_policy_document.scheduler_invoke.statement).effect == "Allow" &&
      one(data.aws_iam_policy_document.scheduler_invoke.statement).actions == toset(["lambda:InvokeFunction"]) &&
      one(data.aws_iam_policy_document.scheduler_invoke.statement).resources == toset([aws_lambda_function.eks_ami_upgrade.arn])
    )
    error_message = "Scheduler may invoke only this Lambda."
  }
  assert {
    condition = (
      length(data.aws_iam_policy_document.scheduler_assume_role.statement) == 1 &&
      one(data.aws_iam_policy_document.scheduler_assume_role.statement).effect == "Allow" &&
      one(data.aws_iam_policy_document.scheduler_assume_role.statement).actions == toset(["sts:AssumeRole"]) &&
      one(data.aws_iam_policy_document.scheduler_assume_role.statement).principals == toset([{
        type        = "Service"
        identifiers = toset(["scheduler.amazonaws.com"])
      }]) &&
      one(data.aws_iam_policy_document.scheduler_assume_role.statement).condition == toset([
        {
          test     = "StringEquals"
          variable = "aws:SourceAccount"
          values   = tolist(["123456789012"])
        },
        {
          test     = "ArnEquals"
          variable = "aws:SourceArn"
          values   = tolist(["arn:aws:scheduler:us-east-2:123456789012:schedule-group/ami-patch-test"])
        }
      ])
    )
    error_message = "Trust only Scheduler from this account and schedule group."
  }
  assert {
    condition = (
      length(data.aws_iam_policy_document.lambda_assume_role.statement) == 1 &&
      one(data.aws_iam_policy_document.lambda_assume_role.statement).effect == "Allow" &&
      one(data.aws_iam_policy_document.lambda_assume_role.statement).actions == toset(["sts:AssumeRole"]) &&
      one(data.aws_iam_policy_document.lambda_assume_role.statement).principals == toset([{
        type        = "Service"
        identifiers = toset(["lambda.amazonaws.com"])
      }])
    )
    error_message = "The Lambda execution role must trust only the Lambda service."
  }
}

run "central_timezone_and_custom_expression" {
  command = plan
  variables {
    schedule_timezone = "America/Chicago"
    rate              = "cron(0 3 * * ? *)"
  }
  assert {
    condition     = output.schedule_timezone == "America/Chicago" && output.schedule_expression == "cron(0 3 * * ? *)"
    error_message = "US Central callers must keep 3 a.m. local time."
  }
}

run "custom_rate" {
  command = plan
  variables {
    rate = "rate(3 days)"
  }
  assert {
    condition     = output.schedule_expression == "rate(3 days)"
    error_message = "Preserve support for custom rate expressions."
  }
}

run "reject_empty_timezone" {
  command = plan
  variables {
    schedule_timezone = " "
  }
  expect_failures = [var.schedule_timezone]
}
