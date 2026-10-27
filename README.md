# terraform-aws-eks-nodegroup-ami-update

Schedule an AWS Lambda function with EventBridge Scheduler to request AMI updates
for the managed node groups of an existing EKS cluster. By default it runs daily
at 3 a.m. UTC. Instantiate the module once per cluster.

## Repository layout

```text
main.tf                AWS resources and policy documents
locals.tf              Shared tag expressions
variables.tf           Module inputs
outputs.tf             Module outputs
versions.tf            Terraform and provider requirements
ami.py                 Lambda source
ami.zip                Reproducible source-only Lambda deployment package
scripts/               Deployment packaging script
tests/                 Python and Terraform regression tests
examples/basic/        Runnable caller configuration
.github/workflows/     Terraform formatting and validation checks
```

This repository contains one reusable module at its root. Supporting submodules
can be added under `modules/` if a concrete reuse need arises.

## Usage

Configure the AWS provider in the caller and use the same region for the provider
and the module. Replace `<release-tag>` with a published, reviewed tag or commit.

```hcl
provider "aws" {
  region = "us-east-2"
}

module "ami_patch" {
  source = "github.com/moonswitch/terraform-aws-eks-nodegroup-ami-update?ref=<release-tag>"

  region  = "us-east-2"
  cluster = "cluster1"

  # Optional: run at 3 a.m. US Central instead of the default UTC.
  schedule_timezone = "America/Chicago"

  tags = {
    Environment = "production"
  }
}
```

See the [basic example](examples/basic/README.md) for local usage.
Use a release or commit containing the root module layout. Source URLs do not
need a module subfolder suffix.

## Requirements

| Dependency | Requirement |
| --- | --- |
| Terraform | >= 1.17.0 |
| hashicorp/aws | >= 6.70.0 |
| Lambda runtime | Python 3.14 (Amazon Linux 2023) |

The caller configures the AWS provider and credentials. Set `region` to match that
provider's region. The module has no backend or provider configuration of its own.
The deployment ZIP is resolved relative to `path.module`, so consumers do not need
a local packaging step.

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `region` | `string` | required | AWS region of the EKS cluster. |
| `cluster` | `string` | required | Existing EKS cluster name. |
| `rate` | `string` | `"cron(0 3 * * ? *)"` | EventBridge Scheduler expression. By default, daily at 3 a.m. in `schedule_timezone`. |
| `schedule_timezone` | `string` | `"UTC"` | IANA time zone for cron schedules; use `America/Chicago` for US Central with daylight saving adjustments. |
| `webhook_url` | `string` | `null` | Optional HTTPS notification endpoint (sensitive). Delivery is best-effort. |
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
| `schedule_arn` | EventBridge Scheduler schedule ARN. |
| `schedule_expression` | Configured schedule expression. |
| `schedule_timezone` | Configured schedule time zone. |
| `lambda_execution_role_arn` | Lambda execution role ARN. |


## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation, packaging, and release guidance.
CI checks formatting and validates the module and examples without AWS credentials
or infrastructure changes. Deployment testing requires a disposable EKS environment.

## Scheduling and time zones

The default `rate = "cron(0 3 * * ? *)"` and `schedule_timezone = "UTC"` run daily
at 03:00 UTC. Set `schedule_timezone = "America/Chicago"` to run at 3 a.m. US
Central throughout the year (CST and CDT). The flexible time window is off;
Scheduler targets the scheduled minute, not an exact second.

Cron expressions follow the selected IANA time zone's daylight saving rules.
If a custom cron time falls in a skipped spring-forward hour, that invocation is
skipped; a repeated fall-back hour invokes only once. The 3 a.m. Chicago example
avoids both ambiguous periods. Rate expressions such as `rate(3 days)` use elapsed
72-hour intervals, so they do not preserve a fixed local clock time across DST.

## Upgrading from EventBridge scheduled rules

This is a breaking change and should be released as a new major version:

- The default changes from `cron(0 0 */3 * ? *)` (midnight UTC on every third day
  of the month) to daily at 3 a.m. UTC. To retain the old timing, explicitly set
  `rate = "cron(0 0 */3 * ? *)"` and `schedule_timezone = "UTC"`.
- Replace output references to `cloudwatch_event_rule_arn` with `schedule_arn`,
  and `cloudwatch_event_rule_schedule_expression` with `schedule_expression`.
  Scheduler ARNs identify a different AWS resource type; update external IAM
  policies or integrations that used the rule ARN.
- Terraform removes the old rule, target, and rule-specific Lambda invocation
  permission, then manages a Scheduler schedule, tagged schedule group, and
  dedicated invocation role/policy. These are different resource types, so no
  state moves are needed. Existing Lambda and Lambda execution-role addresses
  are unchanged. Schedule tags are applied to the schedule group.
- The identity applying Terraform needs Scheduler management permissions and
  permission to pass the new execution role to `scheduler.amazonaws.com`.

Review the plan and apply away from a scheduled invocation time: creation and
removal of the old and new schedules are not atomic, so a transition can briefly
have both or neither active. Do not manually move old rule state to the schedule.

## Runtime behavior

The function uses Python 3.14, which is listed in the [AWS Lambda supported
runtimes](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html).
It uses the configured region, paginates all managed node groups, and requests
an update for each. Requests use bounded SDK retries and timeouts. The Lambda
has a five-minute execution timeout; very large clusters may need a queued or
orchestrated update design to avoid exceeding it.

An update request is asynchronous: notifications report EKS acceptance/status,
not completion of node rotation. Busy node groups are skipped until a later
schedule. Other AWS failures are logged, remaining node groups are attempted,
and the invocation fails so Lambda's asynchronous retries can run. Scheduler
populates the payload `id` from its schedule ARN and scheduled time, producing
stable per-node-group idempotency tokens across delivery and Lambda retries. Manually
invoked events without an `id` use the SDK's default request tokens.

Optional notifications use the `webhook_url` environment variable and HTTPS JSON
POSTs with a five-second timeout. Redirects are not followed. Delivery failures
are logged without the URL and do not retry successful EKS updates; this is
best-effort notification, not guaranteed delivery. `webhook_url` is marked
sensitive in Terraform, but its value still resides in state and Lambda's
environment; protect access to both.

## Permissions and logging

The Lambda execution role is limited to:

- `eks:ListNodegroups` on the configured cluster ARN.
- `eks:UpdateNodegroupVersion` on node groups belonging to that cluster.
- `logs:CreateLogStream` and `logs:PutLogEvents` on this function's log streams.

Scheduler has a separate execution role with only `lambda:InvokeFunction` on
this Lambda. Its trust policy allows `scheduler.amazonaws.com` only for this
account and schedule group. Scheduler assumes that role rather than relying on
the old EventBridge rule's Lambda resource permission. Scheduler delivery retries
and Lambda asynchronous function retries are separate mechanisms.

ARNs use the caller's account and AWS partition. Terraform creates the log group
with 30-day retention. If that log group already exists from a prior deployment,
import it into `aws_cloudwatch_log_group.lambda` before applying. The deployment
identity needs permission to manage these resources; the Lambda role does not
need EC2 permissions, `iam:PassRole`, or log-group creation permissions. EKS uses
its own service-linked roles to perform node-group operations.

## Packaging and validation

The committed ZIP contains only `ami.py`. HTTPS uses Python's standard library;
`boto3` and `botocore` come from the Lambda runtime. AWS therefore controls the
production SDK version; local tests pin a development SDK. If SDK version pinning
becomes necessary, package the complete SDK dependency set together.

CI runs Python 3.14 regression tests, lint and formatting checks, verifies the
ZIP matches source, and checks Terraform permissions and configuration with a
mock provider. These checks do not deploy resources or prove live EKS behavior;
validate updates and notifications on a disposable cluster before production use.
