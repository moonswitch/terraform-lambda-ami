variable "region" {
  description = "AWS region containing the existing EKS cluster."
  type        = string
}

variable "cluster" {
  description = "Name of an existing EKS cluster with managed node groups."
  type        = string
}
