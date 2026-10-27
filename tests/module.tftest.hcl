mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/lambda_execution_role_test" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-2:123456789012:function:update_node_group_function_test" }
  }
  mock_resource "aws_cloudwatch_event_rule" {
    defaults = { arn = "arn:aws:events:us-east-2:123456789012:rule/ami-patch-schedule-test" }
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
