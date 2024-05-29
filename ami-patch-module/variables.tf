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
  default     = null
  type        = string
}

variable "rate" {
  description = "The rate at which the Lambda function will check for AMI updates."
  default     = "cron(0 0 */3 * ? *)"
  type        = string
}

variable "tags" {
  description = "Any other additional tags to be applied to the resources"
  type        = map(string)
  default     = {}
}

variable "default_tags" {
  description = "These tags will be added by default"
  type        = map(string)
  default = {
    forUseBy     = "Terraform"
    managedByIAC = "Yes"
  }
}

locals {
  merge_tags = merge(var.default_tags, var.tags)
}