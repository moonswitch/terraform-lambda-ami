provider "aws" {
  region = var.region
}

module "ami_patch" {
  source = "../.."

  region  = var.region
  cluster = var.cluster

  tags = {
    Environment = "example"
  }
}
