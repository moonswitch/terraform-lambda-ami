# Contributing

## Module conventions

Keep public inputs in `variables.tf`, outputs in `outputs.tf`, requirements in
`versions.tf`, and shared expressions in `locals.tf`. Keep provider configurations
and backends in callers, not in the reusable module. Update the module reference
when changing its interface and keep runnable caller examples in `examples/`.

Keep the reusable module at the repository root and reserve `modules/` for
supporting submodules with a concrete reuse need. Keep runnable deployments
under `examples/`. The planned repository rename is documented in the README.

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

## Lambda packaging

`ami.py` and the committed `ami.zip` currently form the deployment artifact. Source
changes require rebuilding the ZIP with its dependencies and checking that `ami.py`
is at the archive root. Do not replace the ZIP with a source-only archive: the
handler imports `requests`, which needs to be packaged. A reproducible packaging
pipeline is follow-up work; see the repository README for current limitations.

## Releases

Use semantic version tags and document interface, provider compatibility, and
behavior changes in release notes. Validate examples before tagging. Breaking
source-path, input, output, or resource-address changes require a major release
and migration instructions. Before Terraform Registry publication, review the
root-module layout, repository naming, and choose an appropriate license with the
repository owner; this change does not assign a license.
