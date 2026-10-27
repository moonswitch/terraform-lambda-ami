# terraform-aws-eks-nodegroup-ami-update

Schedule an AWS Lambda function to request AMI updates for the managed node groups
of an existing EKS cluster. Instantiate the module once per cluster.

## Repository layout

```text
main.tf                AWS resources and policy documents
locals.tf              Shared tag expressions
variables.tf           Module inputs
outputs.tf             Module outputs
versions.tf            Terraform and provider requirements
ami.py                 Lambda source
ami.zip                Deployment package, including Python dependencies
examples/basic/        Runnable caller configuration
.github/workflows/     Terraform formatting and validation checks
```

This repository contains one reusable module at its root. Supporting submodules
can be added under `modules/` if a concrete reuse need arises.

## Planned repository rename

The intended repository name is `terraform-aws-eks-nodegroup-ami-update`, following
`terraform-<provider>-<purpose>`. The GitHub repository is currently named
`terraform-lambda-ami`; the remote rename has not been performed.

When renaming the repository:

1. Rename it under the `moonswitch` GitHub organization.
2. Update local Git remotes to
   `https://github.com/moonswitch/terraform-aws-eks-nodegroup-ami-update.git`.
3. Update the usage source below to
   `github.com/moonswitch/terraform-aws-eks-nodegroup-ami-update?ref=<release-tag>`
   and check repository links and CI in GitHub.
4. Tag a release containing the root module layout before distributing the module.

There are no existing consumers, so the old module subfolder is removed without
a compatibility wrapper. Source URLs for this layout do not use
`//ami-patch-module`; older tags retain their original layout.

## Usage

Configure the AWS provider in the caller and use the same region for the provider
and the module. Replace `<release-tag>` with a published, reviewed tag or commit.

```hcl
provider "aws" {
  region = "us-east-2"
}

module "ami_patch" {
  source = "github.com/moonswitch/terraform-lambda-ami?ref=<release-tag>"

  region  = "us-east-2"
  cluster = "cluster1"
  rate    = "cron(0 0 */3 * ? *)"

  tags = {
    Environment = "production"
  }
}
```

See the [basic example](examples/basic/README.md) for local usage.
The source above uses the current repository name; use a release or commit
containing this root layout.

## Requirements

| Dependency | Requirement |
| --- | --- |
| Terraform | >= 1.5.0 |
| hashicorp/aws | >= 5.0 |

The caller configures the AWS provider and credentials. Set `region` to match that
provider's region. The module has no backend or provider configuration of its own.
The deployment ZIP is resolved relative to `path.module`, so consumers do not need
a local packaging step.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `region` | `string` | required | AWS region of the EKS cluster. |
| `cluster` | `string` | required | Existing EKS cluster name. |
| `rate` | `string` | `"cron(0 0 */3 * ? *)"` | EventBridge schedule expression, in UTC. The default runs at midnight on every third day of the month, resetting each month. |
| `webhook_url` | `string` | `null` | Notification endpoint; see the known webhook limitation in the repository README. |
| `tags` | `map(string)` | `{}` | Resource tags; override matching default tag keys. |
| `default_tags` | `map(string)` | `{ forUseBy = "Terraform", managedByIAC = "Yes" }` | Baseline resource tags. |

## Outputs

| Name | Description |
| --- | --- |
| `lambda_function_name` | Lambda function name. |
| `lambda_function_arn` | Lambda function ARN. |
| `lambda_function_invoke_arn` | Lambda invoke ARN. |
| `lambda_function_version` | Lambda version reported by the provider. |
| `lambda_function_last_modified` | Lambda last modification timestamp. |
| `cloudwatch_event_rule_arn` | Schedule rule ARN. |
| `cloudwatch_event_rule_schedule_expression` | Configured schedule expression. |
| `lambda_execution_role_arn` | Lambda execution role ARN. |


## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation, packaging, and release guidance.
CI checks formatting and validates the module and examples without AWS credentials
or infrastructure changes. Deployment testing requires a disposable EKS environment.

## Known operational limitations

- The current IAM policy grants broad EKS, EC2, CloudWatch, and `iam:PassRole`
  permissions. Review and narrow it before production use.
- Terraform sets `webhook_url`, but the Python handler reads `webhook-url`.
  Webhook notifications currently need a runtime fix and rebuilt deployment ZIP.
- The checked-in ZIP includes dependencies and development artifacts. A future
  packaging change should pin dependencies, build a clean package, and verify
  compatibility with the Lambda runtime.

These are existing runtime concerns; the repository organization does not resolve them.
