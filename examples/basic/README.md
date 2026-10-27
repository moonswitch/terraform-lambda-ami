# Basic example

Deploy the module for an existing EKS cluster with managed node groups. Supply AWS
credentials through your normal AWS credential chain. The provider and Lambda
configuration both use the supplied region.

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars to select your existing cluster and region.
terraform init
terraform plan
```

Review the plan before applying. Applying creates a scheduled function that can
update the cluster's node groups; use a disposable cluster for evaluation.
`terraform destroy` removes the resources created by this example, not the existing
cluster or any AMI updates already performed.

The local source (`../..`) tests this checkout. For independent use, replace the
module's `source` in `main.tf` with:

```hcl
source = "github.com/moonswitch/terraform-aws-eks-nodegroup-ami-update?ref=<release-tag>"
```

Replace `<release-tag>` with a published, reviewed tag or commit containing the
root module layout. See the [repository README](../../README.md) for full usage.
