output "lambda_function_arn" {
  description = "ARN of the scheduled AMI update Lambda function."
  value       = module.ami_patch.lambda_function_arn
}
