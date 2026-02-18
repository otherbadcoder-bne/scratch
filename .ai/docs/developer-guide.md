# Wiki.js Deployment Developer Guide

This guide provides instructions for developers working on the `wiki.js` Terraform project within this repository. It covers everything from local setup to deployment and architecture.

## 1. Introduction

This repository is a personal workspace for infrastructure-as-code experiments. The `wiki.js/` directory contains a standalone Terraform project to deploy a Wiki.js instance on AWS. The architecture is designed to be simple, secure, and cost-effective.

## 2. Repository Structure

The repository is structured as a collection of independent projects in subdirectories.

-   `wiki.js/`: The root module for the Wiki.js Terraform deployment.
    -   `*.tf`: Terraform source files defining the AWS infrastructure.
    -   `tests/`: Terraform test files (`*.tftest.hcl`).
    -   `docker-compose.yml`: Defines the Wiki.js and PostgreSQL services.
    -   `user-data.sh.tftpl`: EC2 user data script to launch the Docker containers.
    -   `.checkov.yml` / `.trivyignore`: Configuration for security scanning exceptions.
-   `.github/workflows/`: GitHub Actions CI workflows for pull requests.
-   `scripts/`: Helper scripts used by pre-commit hooks (e.g., `ai-review.sh`, `update-infracost.sh`).
-   `.pre-commit-config.yaml`: Defines the local pre-commit and pre-push hooks.
-   `AGENTS.md`: A guide for AI agents providing high-level context about the repository's purpose and conventions.

## 3. Local Development Setup

This project uses `pre-commit` to automate linting, formatting, security scanning, and cost estimation.

### 3.1. Prerequisites

The following tools must be installed on your system.

**macOS:**
```bash
# Install core tools
brew install git pre-commit terraform tflint trivy gitleaks checkov terraform-docs infracost

# Install Gemini CLI for the AI review hook
# See https://github.com/google-gemini/gemini-cli for instructions
```

**Windows:**
```powershell
# Install core tools via Chocolatey and Pip
choco install git terraform tflint trivy gitleaks terraform-docs infracost
pip install pre-commit checkov

# Install Gemini CLI for the AI review hook
# See https://github.com/google-gemini/gemini-cli for instructions
```

### 3.2. Activate Hooks

Once the prerequisites are installed, activate the hooks in your local repository clone:

```bash
# Install commit-time hooks
pre-commit install

# Install the pre-push AI review hook (requires a separate command)
pre-commit install --hook-type pre-push
```

### 3.3. Authenticate Infracost

The `infracost` hook requires an API key to provide cost estimates.
```bash
infracost auth login
```

## 4. Environment Variables and Configuration

### 4.1. Terraform Variables

The infrastructure is configured via variables defined in `wiki.js/variables.tf`.

-   `domain_name` (string, **required**): The domain name for the Wiki.js site (e.g., `wiki.example.com`).
-   `vpc_cidr` (string, optional): CIDR block for the VPC. Defaults to `10.0.0.0/16`.
-   `instance_type` (string, optional): EC2 instance type. Defaults to `t3.micro`.
-   `environment` (string, optional): Environment name for tagging resources. Defaults to `shared-services`.
-   `schedule_enabled` (bool, optional): If `true`, the EC2 instance will automatically stop and start to save costs. Defaults to `true`.

Create a `terraform.tfvars` file inside the `wiki.js/` directory to set these values, for example:
```tf
domain_name = "wiki.your-domain.com"
```

### 4.2. AWS Credentials

Terraform requires AWS credentials to manage resources. Configure them using standard methods, such as environment variables:
```bash
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"
export AWS_DEFAULT_REGION="ap-southeast-2"
```

## 5. Deployment Process

The infrastructure is managed entirely by Terraform.

### 5.1. Deploying the Infrastructure

1.  Navigate to the project directory:
    ```bash
    cd wiki.js/
    ```

2.  Initialize Terraform:
    ```bash
    terraform init
    ```

3.  Review the planned changes:
    ```bash
    terraform plan
    ```

4.  Apply the changes to deploy the infrastructure:
    ```bash
    terraform apply
    ```

### 5.2. Post-Deployment Steps

After a successful `terraform apply`, two manual steps are required to make the site accessible:

1.  **ACM Certificate Validation**: The `acm_validation_records` output contains the CNAME record that must be created in your DNS provider to validate the TLS certificate.

2.  **DNS CNAME for CloudFront**: The `cloudfront_domain_name` output provides the target for your site's primary CNAME record (e.g., create a CNAME for `wiki.your-domain.com` pointing to the `*.cloudfront.net` address).

You can get these values by running `terraform output`.

## 6. Running Tests

The repository uses native Terraform tests, which are executed as part of the pre-commit hook suite.

-   Test files are located in `wiki.js/tests/` (`cloudfront.tftest.hcl`, `ec2.tftest.hcl`, `vpc.tftest.hcl`).
-   The `terraform_test` hook in `.pre-commit-config.yaml` automatically finds and runs these tests.

To run all tests and other checks manually:
```bash
pre-commit run --all-files
```

To run only the Terraform tests, navigate to the `wiki.js/` directory and run:
```bash
terraform test
```
> **Note**: Running `terraform test` may require active AWS credentials.

## 7. Branching and Pull Requests

### 7.1. Branching Strategy

-   Direct commits to the `main` branch are blocked.
-   All work should be done on `develop` or a feature branch (e.g., `feat/my-change`).
-   Changes are merged into `main` via Pull Requests (PRs).

### 7.2. Automated Checks

**Pre-Commit & Pre-Push Hooks:**
-   On `git commit`, a suite of tools will format, lint, and scan your Terraform code for issues, secrets, and misconfigurations.
-   On `git push`, a unique AI-powered hook (`scripts/ai-review.sh`) analyzes the diff for logic flaws, architectural drift, and other issues that static tools cannot catch. It will block the push if it finds a critical issue. To bypass this, use `git push --no-verify`.

**GitHub Actions CI:**
When a PR is opened against `main`, two workflows are triggered:
1.  **`terraform-ci.yml`**: Runs a comprehensive set of checks (format, validate, tflint, trivy, checkov, gitleaks) and then executes a `terraform plan`. The plan output is posted as a comment on the PR for review.
2.  **`infracost.yml`**: Posts a PR comment with a detailed cost breakdown of the infrastructure changes.

## 8. Code Architecture Walkthrough

The infrastructure is modular and defined across several key files in the `wiki.js/` directory.

-   **`main.tf`**: The entry point. It configures the Terraform version and the required AWS providers. It defines two `aws` providers: one for the primary region (`ap-southeast-2`) and an alias for `us-east-1`, which is required for CloudFront and ACM resources.

-   **`vpc.tf`**: Creates the networking stack, including a VPC, 3 public and 3 private subnets, an Internet Gateway, and associated route tables. It follows security best practices by explicitly restricting the default security group and default network ACLs.

-   **`ec2.tf`**: Provisions the `t3.micro` EC2 instance. This file defines the IAM role for SSM access (allowing shell access without SSH keys), a security group to allow ingress traffic from CloudFront on port 3000, and the instance itself, which uses a user data script to launch the application via Docker Compose.

-   **`docker-compose.yml`**: This file, used by the EC2 user data script, defines the application services. It sets up the `postgres:15-alpine` database container and the `ghcr.io/requarks/wiki:2` application container, linking them and persisting database data to a Docker volume.

-   **`cloudfront.tf`**: Defines the CloudFront distribution that acts as the public-facing entry point. It terminates TLS, redirects all HTTP traffic to HTTPS, and attaches a response headers policy to apply security headers like HSTS and X-Frame-Options.

-   **`acm.tf`**: Provisions the `aws_acm_certificate` in `us-east-1` using DNS validation. The validation details are exposed as a Terraform output.

-   **`scheduler.tf`**: Creates an optional, cost-saving schedule (`var.schedule_enabled`). It uses EventBridge Scheduler to trigger SSM Automation documents that stop the EC2 instance in the evening and start it in the morning (AEST).

-   **`outputs.tf`**: Exposes important information about the created resources, such as the EC2 instance ID, CloudFront domain name, and the DNS records required for ACM validation.

## 9. Common Development Tasks

### 9.1. Making a Code Change

1.  Create a new branch from `develop`: `git checkout -b feat/my-new-feature`.
2.  Modify the Terraform code in the `wiki.js/` directory.
3.  Commit your changes: `git commit -m "feat: Describe your change"`. The pre-commit hooks will run automatically.
4.  If the hooks pass, push your branch: `git push`. The pre-push AI review will run.
5.  Open a Pull Request against the `main` branch in GitHub.

### 9.2. Connecting to the Instance

Direct SSH access is disabled. Access the instance shell using AWS SSM Session Manager.

1.  Get the instance ID from Terraform outputs:
    ```bash
    terraform -chdir=wiki.js output instance_id
    ```
2.  Start a session:
    ```bash
    aws ssm start-session --target <instance-id-from-output>
    ```

### 9.3. Managing Security Scan Exceptions

If a security tool flags a resource incorrectly, you can add a documented exception.
-   **Trivy**: Add the rule ID, resource, and a justification comment to `.trivyignore`.
-   **Checkov**: Add a `skip-check` block to `.checkov.yml` with a comment explaining the reason. Inline `#checkov:skip=` comments are also used for some checks.

Every exception must include a clear, documented reason.
