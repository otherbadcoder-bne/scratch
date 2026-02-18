# Scratch Pad

This is just a general space for me to spew my (terrible) code up into.

## Pre-commit Hooks

This repo uses [pre-commit](https://pre-commit.com/) to run formatting, linting, security, and policy checks before each commit.

### 1. Install pre-commit

**macOS**
```bash
brew install pre-commit
```

**Windows**
```powershell
pip install pre-commit
```

### 2. Install hook dependencies

The following tools must be installed on your system — pre-commit calls them but does not install them for you.

**macOS**
```bash
brew install tflint trivy gitleaks checkov terraform-docs infracost
```

**Windows**
```powershell
choco install tflint trivy gitleaks terraform-docs infracost
pip install checkov
```

> **Note:** checkov is configured as a `system` hook (not managed by pre-commit) because its Python dependency `rustworkx` fails to compile in pre-commit's isolated environment. It must be installed separately as shown above.

> **Note:** infracost requires an API key. Run `infracost auth login` after installing to authenticate.

### 3. Activate the hooks

```bash
pre-commit install                        # commit-time hooks
pre-commit install --hook-type pre-push   # pre-push AI review hook
```

Both commands are required. `pre-commit install` alone will not wire up the pre-push hook.

### 4. (Optional) Run against all files

```bash
pre-commit run --all-files
```

### Hooks included

**Commit-time** (run on every `git commit`):

| Hook | Purpose |
|---|---|
| `terraform_fmt` | Canonical formatting |
| `terraform_validate` | Syntax and config validation |
| `terraform_tflint` | Terraform linter |
| `terraform_test` | Terraform native tests (requires AWS creds) |
| `terraform_docs` | Auto-generate module documentation |
| `terraform_trivy` | Security scanner (HIGH/CRITICAL) |
| `gitleaks` | Secret / credential detection |
| `checkov` | Policy-as-code (CIS benchmarks) |
| `infracost` | Cost estimation for infrastructure changes |
| `detect-private-key` | Blocks commits containing private keys |
| `no-commit-to-branch` | Prevents direct commits to main |

**Pre-push** (run on every `git push`, requires `pre-commit install --hook-type pre-push`):

| Hook | Purpose |
|---|---|
| `ai-review` | Agentic review via `claude --print` — reasons about intent, security logic, and architectural drift beyond what static tools catch. Blocks push on serious findings. Requires `claude` CLI. Override with `git push --no-verify`. |

## GitHub Actions

CI runs on every PR to `main`. The following **repository secrets** must be configured under *Settings → Secrets and variables → Actions*:

| Secret | Used by | Purpose |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Terraform CI | AWS credentials for `terraform plan` and tests |
| `AWS_SECRET_ACCESS_KEY` | Terraform CI | AWS credentials for `terraform plan` and tests |
| `AWS_DEFAULT_REGION` | Terraform CI | AWS region (e.g. `ap-southeast-2`) |
| `INFRACOST_API_KEY` | Infracost | API key from `infracost auth login` |

> `GITHUB_TOKEN` is provided automatically — no setup needed.
