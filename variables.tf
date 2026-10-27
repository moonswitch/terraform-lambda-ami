variable "region" {
  description = "The AWS region of the EKS cluster."
  type        = string
}

variable "cluster" {
  description = "The name of the EKS cluster."
  type        = string
}

variable "webhook_url" {
  description = "Optional HTTPS notification endpoint. Delivery failures are logged without failing AMI update requests."
  sensitive   = true
  default     = null
  type        = string

  validation {
    condition     = var.webhook_url == null ? true : can(regex("^https://[^/@\\s]+(/[^\\s]*)?$", var.webhook_url))
    error_message = "webhook_url must be null or an HTTPS URL without user information."
  }
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
