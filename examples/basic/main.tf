provider "aws" {
  region = var.region
}

module "ami_patch" {
  source = "../.."

  region  = var.region
  cluster = var.cluster

  # Run daily at 3 a.m. US Central, adjusting automatically for daylight saving.
  schedule_timezone = "America/Chicago"

  tags = {
    Environment = "example"
  }
}
