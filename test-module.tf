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
  region = "us-east-2"
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

  region  = "us-east-2"
  cluster = "some-test-cluster"
}