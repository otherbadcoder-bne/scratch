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
pre-commit install
```

### 4. (Optional) Run against all files

```bash
pre-commit run --all-files
```

### Hooks included

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
