# Agent Context

This file helps AI agents quickly understand the purpose, structure, and conventions of this repository.

## What is this repo?

A **scratch/sandbox repository** for infrastructure-as-code experiments and small deployments. It is not a monorepo or a product — it's a personal workspace where individual projects live in subdirectories. Each subdirectory is an independent Terraform root module.

## Current projects

### `wiki.js/`
Deploys a **Wiki.js** instance on AWS using Terraform. Architecture:
- Shared services VPC (3 public + 3 private subnets across 3 AZs)
- EC2 (t3.micro, Amazon Linux 2023) running Wiki.js + PostgreSQL via Docker Compose
- CloudFront distribution for TLS termination (origin hits EC2 port 3000 over HTTP)
- ACM certificate with DNS validation (Route53 is in a separate AWS account)
- SSM Session Manager for shell access (no SSH)
- Security headers policy on CloudFront (HSTS, X-Frame-Options, etc.)

Key files: `main.tf`, `vpc.tf`, `ec2.tf`, `cloudfront.tf`, `acm.tf`, `variables.tf`, `outputs.tf`, `docker-compose.yml`, `user-data.sh.tftpl`

## Repository conventions

### Branching
- `main` is protected — no direct commits (enforced by pre-commit hook `no-commit-to-branch`)
- Work on `develop` or feature branches, merge via PR
- GitHub Actions CI runs on PRs to `main`

### Pre-commit hooks
Defined in `.pre-commit-config.yaml` at the repo root. Hooks run in this order:
1. **Terraform** — fmt, validate, tflint, terraform-docs, trivy
2. **Infracost** — cost breakdown injected into project README between `<!-- BEGIN_INFRACOST -->` / `<!-- END_INFRACOST -->` markers
3. **File hygiene** — trailing whitespace, end-of-file fixer, YAML/JSON checks, merge conflict detection, private key detection
4. **Gitleaks** — secret scanning
5. **Checkov** — policy-as-code (skips configured in each project's `.checkov.yml`)

Hook ordering matters — generators (terraform-docs, infracost) run before file hygiene so whitespace gets cleaned in the same pass.

### Security scanning exceptions
- **Trivy**: ignored rules go in each project's `.trivyignore` file with full documentation (rule ID, resource, reason)
- **Checkov**: skips go in each project's `.checkov.yml` via `skip-check` list (inline `#checkov:skip=` comments are unreliable for `CKV2_*` graph-based checks)
- Every exception must include a documented reason

### Infracost
- Pre-commit hook injects cost breakdown into project READMEs automatically
- GitHub Actions workflow posts cost comments on PRs
- Uses `--no-color` and `--log-level error` to keep output clean
- Requires `INFRACOST_API_KEY` as a GitHub Actions secret

### Terraform docs
- Auto-generated via `terraform-docs` into project READMEs between `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers
- Config in `.terraform-docs.yml` (exists at both repo root and in each project directory)

### CI/CD (GitHub Actions)
Two workflows in `.github/workflows/`:
- **`terraform-ci.yml`** — runs on PRs to main: format check, validate, tflint, trivy, checkov, gitleaks, then terraform plan (posted as PR comment)
- **`infracost.yml`** — runs on PRs to main: posts cost estimate comment on PR

AWS credentials for CI use static IAM user keys (stored as Actions secrets). OIDC federation is a future improvement.

### GitHub Actions secrets required
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_DEFAULT_REGION` — for terraform plan
- `INFRACOST_API_KEY` — for cost estimation

## Important syntax reminders
- **Trivy inline ignore**: `#trivy:ignore:AVD-AWS-0011` (above the resource, uses `AVD-` prefix)
- **Checkov inline skip**: `#checkov:skip=CKV_AWS_123 reason` (separator is `=` not `:`)
- **Checkov graph checks** (`CKV2_*`): inline skips don't work — use `--skip-check` or `.checkov.yml`

## Adding a new project
1. Create a new subdirectory (e.g. `my-project/`)
2. Add Terraform files
3. Add a `README.md` with `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers (and optionally `<!-- BEGIN_INFRACOST -->` / `<!-- END_INFRACOST -->`)
4. Add `.checkov.yml` and `.trivyignore` if needed
5. Copy `.terraform-docs.yml` into the directory
6. Update `.github/workflows/` paths if CI should cover the new project
