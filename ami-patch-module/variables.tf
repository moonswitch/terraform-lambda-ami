variable "region" {
  description = "The AWS region of the EKS cluster."
  type        = string
}

variable "cluster" {
  description = "The name of the EKS cluster."
  type        = string
}

variable "webhook_url" {
  description = "Webhook URL"
  type        = string
}

variable "rate" {
  description = "The rate at which the Lambda function will check for AMI updates."
  default     = "cron(0 0 */3 * ? *)"
  type        = string
}
