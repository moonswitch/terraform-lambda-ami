# terraform-lambda-ami
Usage:
```
module "test" {
  source = "github.com/moonswitch/terraform-lambda-ami//ami-patch-module?ref=main"

  region      = "us-east-2"
  cluster     = "some-test-cluster"
  rate        = "cron(0 0 */3 * ? *)"
  webhook_url = "webhook_url"
}
```
