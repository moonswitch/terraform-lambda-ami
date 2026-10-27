# Contributing

## Module conventions

Keep public inputs in `variables.tf`, outputs in `outputs.tf`, requirements in
`versions.tf`, and shared expressions in `locals.tf`. Keep provider configurations
and backends in callers, not in the reusable module. Update the module reference
when changing its interface and keep runnable caller examples in `examples/`.
Define IAM permissions and role trust policies with `aws_iam_policy_document`
data sources rather than hand-encoding JSON.

Keep the reusable module at the repository root and reserve `modules/` for
supporting submodules with a concrete reuse need. Keep runnable deployments
under `examples/`. The canonical repository is
[`moonswitch/terraform-aws-eks-nodegroup-ami-update`](https://github.com/moonswitch/terraform-aws-eks-nodegroup-ami-update).

## Validation

Run from the repository root with Terraform >= 1.17.0:

```sh
terraform fmt -check -recursive
for directory in . examples/*; do
  terraform -chdir="$directory" init -backend=false -input=false
  terraform -chdir="$directory" validate
done
```

Initialization downloads providers but validation requires no AWS credentials.
CI uses Terraform 1.17.0, the current stable release when this baseline was chosen.
The workflow pins that version for reproducibility and tests the exact declared
minimum. With no existing consumers, there is no older-version compatibility
requirement. Update the CI pin, module and example requirements, and documentation
together when raising the baseline; add a version matrix if compatibility needs
justify one.
These checks validate syntax and provider schemas; they do not verify IAM behavior,
Lambda execution, or node group updates. Test runtime changes against a disposable
EKS cluster before release.

The library's local `.terraform.lock.hcl` is ignored because callers select their
own provider versions; a child module's lock file does not pin its consumers.
Examples in this repository are validation fixtures and also ignore local locks.
Real deployment root configurations should commit their own lock files. State,
plans, local variable values, and credentials must stay out of version control.

## Python development and Lambda packaging

Use Python 3.14 for development and the Lambda runtime:

```sh
python3.14 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/python scripts/package_lambda.py
terraform test
```

The packaging script writes a deterministic `ami.zip` containing only `ami.py`.
Rebuild and commit the ZIP whenever source changes. CI rebuilds it and rejects
source/archive drift. Do not include virtual environments, caches, or pip in the
artifact. The function uses standard-library HTTPS and the AWS SDK supplied by
Lambda; `requirements-dev.txt` is for local tests and tooling only.

Python tests use SDK stubs and mocked HTTP transport without AWS credentials or
live updates. Terraform tests use a mock provider to verify runtime, webhook
configuration, and IAM scopes. Runtime changes also require a disposable EKS
integration check before production rollout.

## Releases

Use semantic version tags and document interface, provider compatibility, and
behavior changes in release notes. Validate examples before tagging. Breaking
source-path, input, output, or resource-address changes require a major release
and migration instructions. Before Terraform Registry publication, review the
root-module layout, repository naming, and choose an appropriate license with the
repository owner; this change does not assign a license.
