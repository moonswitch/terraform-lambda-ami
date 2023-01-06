terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    local = {
      version = "~> 2.1"
    }
  }
}

provider "aws" {
  region = var.region
}

terraform {
  cloud {
    organization = "Moonswitch"

    workspaces {
      tags = ["lambda"]
    }
  }
}

module "test" {
  source = "./ami-patch-module"

  processing_lambda_name      = "eks-ami-patcher"
  processing_lambda_role_name = "eks-ami-patcher-role"
  schedule_name               = "ami-patch-event"
  schedule                    = "rate(1 day)"
  runtime                     = "python3.8"
}

variable "region" {}