output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.eks_ami_upgrade.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.eks_ami_upgrade.arn
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.eks_ami_upgrade.invoke_arn
}

output "lambda_function_version" {
  description = "The version of the Lambda function"
  value       = aws_lambda_function.eks_ami_upgrade.version
}

output "lambda_function_last_modified" {
  description = "The date and time when the Lambda function was last modified"
  value       = aws_lambda_function.eks_ami_upgrade.last_modified
}

output "cloudwatch_event_rule_arn" {
  description = "The ARN of the CloudWatch Events rule"
  value       = aws_cloudwatch_event_rule.ami_lambda_schedule.arn
}

output "cloudwatch_event_rule_schedule_expression" {
  description = "The schedule expression of the CloudWatch Events rule"
  value       = aws_cloudwatch_event_rule.ami_lambda_schedule.schedule_expression
}

output "lambda_execution_role_arn" {
  description = "The ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}
