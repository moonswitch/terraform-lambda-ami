# terraform-lambda-ami

The following terraform module is for auto-patching the EKS cluster nodegroups AMI to latest by periodically running a lambda function to check for updates. Having the latest patch is best practice for your EKS nodegroups. For multiple clusters in the same region, simply reuse the module for each cluster.

## Usage:
```
module "ami_patch_cluster1" {
  source = "github.com/moonswitch/terraform-lambda-ami//ami-patch-module?ref=<version>"

  region      = "us-east-2"
  cluster     = "cluster1"
  rate        = "cron(0 0 */3 * ? *)"
  webhook_url = "webhook_url"
}

module "ami_patch_cluster2" {
  source = "github.com/moonswitch/terraform-lambda-ami//ami-patch-module?ref=v1.0.0"

  region      = "us-east-2"
  cluster     = "cluster2"
  rate        = "cron(0 0 */3 * ? *)"
  webhook_url = "webhook_url"
}
```

## Inputs:  
  
`region`      - Required: The region of your EKS cluster  
  
`cluster`     - Required: The name of your EKS cluster  
  
`rate`        - Optional: The rate at which the Lambda function should run to check for updates (Default 00:00 UTC every three days)  
  
`webhook-url` - Optional: URL endpoint for status of nodegroup updates (Default JSON Serialization is string).   


## Outputs

`lambda_function_name`                      - The name of the Lambda function  

`lambda_function_arn`                       - The ARN of the Lambda function  

`lambda_function_invoke_arn`                - The invoke ARN of the Lambda function  

`lambda_function_version`                   - The version of the Lambda function  

`lambda_function_last_modified`             - The date and time when the Lambda function was last modified  

`cloudwatch_event_rule_arn`                 - The ARN of the CloudWatch Events rule  

`cloudwatch_event_rule_schedule_expression` - The schedule expression of the CloudWatch Events rule  

`lambda_execution_role_arn`                 - The ARN of the IAM role used by the Lambda function  
  
