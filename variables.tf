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
  description = "EventBridge Scheduler expression. Cron expressions use schedule_timezone; rate expressions use elapsed time."
  default     = "cron(0 3 * * ? *)"
  type        = string
}

variable "schedule_timezone" {
  description = "IANA time zone used to evaluate cron schedules, for example UTC or America/Chicago."
  type        = string
  default     = "UTC"
  nullable    = false

  validation {
    condition     = length(trimspace(var.schedule_timezone)) > 0
    error_message = "schedule_timezone must be a non-empty IANA time zone name."
  }
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
