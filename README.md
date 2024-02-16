# terraform-lambda-ami
Usage:
```
module "test" {
  source = "./ami-patch-module"

  region  = "us-east-2"
  cluster = "some-test-cluster"
  rate    = "cron(0 0 */3 * ? *)"
}
```