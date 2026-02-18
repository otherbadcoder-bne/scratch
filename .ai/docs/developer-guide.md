# Wiki.js Deployment Developer Guide

This guide provides instructions for developers working on the `wiki.js` Terraform project within this repository. It covers everything from local setup to deployment and architecture.

## 1. Introduction

This repository serves as a personal workspace for infrastructure-as-code experiments and small deployments. The `wiki.js/` directory contains a standalone Terraform project designed to deploy a Wiki.js instance on AWS. The architecture emphasizes simplicity, security, and cost-effectiveness.

## 2. Repository Structure

The `scratch` repository is structured as a collection of independent projects in subdirectories. The `wiki.js/` directory is one such project, acting as a root Terraform module.

-   `wiki.js/`: The root module for the Wiki.js Terraform deployment.
    -   `*.tf`: Terraform source files defining the AWS infrastructure (e.g., `main.tf`, `vpc.tf`, `ec2.tf`, `cloudfront.tf`, `acm.tf`, `variables.tf`, `outputs.tf`, `scheduler.tf`).
    -   `tests/`: Contains Terraform test files (`*.tftest.hcl`).
    -   `docker-compose.yml`: Defines the Wiki.js and PostgreSQL services using Docker Compose.
    -   `user-data.sh.tftpl`: The EC2 user data script responsible for launching Docker containers.
    -   `.checkov.yml` / `.trivyignore`: Configuration files for security scanning exceptions.
-   `.github/workflows/`: Contains GitHub Actions CI workflows for pull requests (e.g., `terraform-ci.yml`, `infracost.yml`).
-   `scripts/`: Holds helper scripts used by pre-commit hooks, such as `ai-review.sh` and `update-infracost.sh`.
-   `.pre-commit-config.yaml`: Defines the local pre-commit and pre-push hooks for code quality and security.
-   `AGENTS.md`: Provides high-level context about the repository's purpose and conventions for AI agents.
-   `README.md`: The root repository README, detailing overall project context and local setup.

## 3. Local Development Setup

This project uses `pre-commit` hooks to automate linting, formatting, security scanning, and cost estimation before code is committed or pushed.

### 3.1. Prerequisites

The following tools must be installed on your local system:

**macOS:**
```bash
brew install git pre-commit terraform tflint trivy gitleaks checkov terraform-docs infracost
# Install Gemini CLI for the AI review hook (refer to its documentation)
```

**Windows:**
```powershell
choco install git terraform tflint trivy gitleaks terraform-docs infracost
pip install pre-commit checkov
# Install Gemini CLI for the AI review hook (refer to its documentation)
```

### 3.2. Activate Hooks

After installing the prerequisites, activate the Git hooks in your local repository clone from the repository root:
```bash
pre-commit install                        # Installs commit-time hooks
pre-commit install --hook-type pre-push   # Installs the pre-push AI review hook
```

### 3.3. Authenticate Infracost

The `infracost` hook requires an API key to provide cost estimates for infrastructure changes. Authenticate by running:
```bash
infracost auth login
```

## 4. Environment Variables and Configuration

The `wiki.js` infrastructure is configured through variables defined in `wiki.js/variables.tf`. These can be set via `terraform.tfvars`, environment variables, or the command line.

-   `domain_name` (string, **required**): The domain name intended for the Wiki.js site (e.g., `wiki.example.com`).
-   `vpc_cidr` (string, optional): Specifies the CIDR block for the shared services VPC. Defaults to `"10.0.0.0/16"`.
-   `instance_type` (string, optional): Defines the EC2 instance type for the Wiki.js server. Defaults to `"t3.micro"`.
-   `environment` (string, optional): A name used for tagging AWS resources. Defaults to `"shared-services"`.
-   `schedule_enabled` (bool, optional): Controls whether the automatic stop/start schedule for the EC2 instance is enabled for cost savings. Defaults to `true`.

## 5. How to Run the Application Locally

The Wiki.js application and its PostgreSQL database run as Docker containers orchestrated by Docker Compose. This allows for local development and testing before deploying to AWS.

1.  Ensure Docker Desktop or Docker Engine is running on your machine.
2.  Navigate to the `wiki.js/` directory within the repository:
    ```bash
    cd wiki.js/
    ```
3.  Start the Wiki.js and PostgreSQL services in detached mode:
    ```bash
    docker-compose up -d
    ```
4.  To stop the services, run:
    ```bash
    docker-compose down
    ```

## 6. How to Run Tests

The `wiki.js` project includes Terraform native tests located in the `wiki.js/tests/` directory.

To run all Terraform tests for the `wiki.js` module:

1.  Navigate to the `wiki.js/` directory:
    ```bash
    cd wiki.js/
    ```
2.  Execute the Terraform test command:
    ```bash
    terraform test
    ```
These tests are also automatically executed as part of the `terraform_test` pre-commit hook during `git commit`. You can manually run all commit-time hooks with `pre-commit run --all-files` from the repository root.

## 7. Deployment Process

The deployment of the `wiki.js` infrastructure to AWS is managed through GitHub Actions workflows.

-   **Branching Model**: Work is done on `develop` or feature branches and merged into `main` via Pull Requests. Direct commits to `main` are prevented by a pre-commit hook.
-   **CI/CD Workflows**: Defined in `.github/workflows/`, these workflows run on Pull Requests targeting the `main` branch:
    -   `terraform-ci.yml`: Performs Terraform formatting checks, validation, `tflint`, `trivy`, `checkov`, `gitleaks` scans, and generates a `terraform plan` which is posted as a PR comment.
    -   `infracost.yml`: Posts a cost estimate comment on the Pull Request.
-   **AWS Credentials**: CI workflows utilize static IAM user keys (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`) stored as GitHub Actions secrets for Terraform plan execution. `INFRACOST_API_KEY` is also required.

## 8. Branching and PR Conventions

-   **Protected Branch**: The `main` branch is protected, and direct commits are not allowed.
-   **Development Flow**: All development work should occur on the `develop` branch or dedicated feature branches.
-   **Merge via Pull Request**: Changes are integrated into the `main` branch through Pull Requests, which trigger GitHub Actions CI workflows for validation and review.

## 9. Code Architecture Walkthrough

### Overall System Overview

The Wiki.js deployment provides a single Wiki.js instance running on AWS, entirely provisioned and managed using Terraform. The architecture emphasizes simplicity, security, and cost-efficiency. The Wiki.js application and its PostgreSQL database run within Docker containers on a single EC2 instance. Public access is facilitated by a CloudFront distribution, which handles TLS termination and applies security headers.

### Component Diagram

```
+---------------+      +--------------------------+      +-------------------+
|     User      |------|  CloudFront Distribution |------|   EC2 Instance    |
|   (Browser)   |      |  (TLS, Security Headers) |      | (Docker: Wiki.js, |
+---------------+      +--------------------------+      |    PostgreSQL)    |
         ^                       |                        +----------+--------+
         |                       |                                 |
         |                       | SSM Session Manager             | EBS Volume
         |                       +---------------------------------+ (db-data)
         |                                ^
         |                                | EventBridge Scheduler
         +--------------------------------+ (Stop/Start EC2)
```

### AWS Services and Their Roles

-   **EC2 (`wiki.js/ec2.tf`)**: A single `t3.micro` instance (by default) runs Amazon Linux 2023 and the Docker engine. Its AMI is dynamically sourced via SSM Parameter Store.
-   **Docker Compose (`wiki.js/user-data.sh.tftpl`, `wiki.js/docker-compose.yml`)**: Orchestrates the Wiki.js (`ghcr.io/requarks/wiki:2`) and PostgreSQL (`postgres:15-alpine`) containers on the EC2 host.
-   **VPC (`wiki.js/vpc.tf`)**: A dedicated VPC (`10.0.0.0/16` by default) with 3 public and 3 private subnets across three availability zones provides network isolation.
-   **Internet Gateway (`wiki.js/vpc.tf`)**: Provides internet access for the public subnets.
-   **Security Groups (`wiki.js/ec2.tf`)**: A security group acts as a stateful firewall for the EC2 instance, allowing ingress traffic only from the CloudFront managed prefix list on TCP port 3000.
-   **Network ACLs (`wiki.js/vpc.tf`)**: Stateless firewalls for public and private subnets, providing an additional layer of defense.
-   **CloudFront (`wiki.js/cloudfront.tf`)**: Serves as the public entry point, providing TLS termination, redirecting HTTP to HTTPS, and enforcing security headers on responses.
-   **IAM (`wiki.js/ec2.tf`, `wiki.js/scheduler.tf`)**:
    -   An **EC2 Instance Role** grants the instance permissions for SSM connectivity (`AmazonSSMManagedInstanceCore`).
    -   A **Scheduler Role** allows EventBridge to start and stop the EC2 instance via SSM Automation documents.
-   **ACM (`wiki.js/acm.tf`)**: Provisions and manages the public SSL/TLS certificate used by CloudFront, created in `us-east-1` as required.
-   **SSM (Systems Manager) (`wiki.js/ec2.tf`)**:
    -   **Session Manager**: Provides secure, shell-based access to the EC2 instance without requiring SSH.
    -   **Parameter Store**: Used to fetch the latest Amazon Linux 2023 AMI ID.
-   **EventBridge Scheduler (`wiki.js/scheduler.tf`)**: Automates the EC2 instance's stop/start schedule for cost optimization.

### Data Flow

1.  **User Request**: A user accesses the wiki via `var.domain_name` in their browser. The request is sent over HTTPS (port 443) to AWS CloudFront.
2.  **CloudFront**: The CloudFront distribution terminates the TLS connection using an ACM certificate. It forwards the request to the EC2 instance (origin) over HTTP on port 3000. Security headers are injected into the response.
3.  **EC2 & Security Group**: The EC2 instance's security group allows the request from the CloudFront managed prefix list on TCP port 3000.
4.  **Docker & Application**: The EC2 instance's user data script configures Docker Compose. The request is received by the `ghcr.io/requarks/wiki:2` container.
5.  **Database**: The Wiki.js application communicates with the `postgres:15-alpine` container over the internal Docker network. PostgreSQL data is persisted on the host's EBS volume via a Docker volume mount (`db-data`).
6.  **Response**: The response travels back through the same path to the user.
Administrative access to the EC2 instance is handled exclusively via SSM Session Manager.

## 10. Common Development Tasks

### Running Pre-commit Hooks Manually

To run all commit-time pre-commit hooks against all files in the repository (useful for checking changes before committing):
```bash
pre-commit run --all-files
```

### Managing Security Scanning Exceptions

The repository utilizes Trivy and Checkov for automated security scanning. Any exceptions to these scans must be properly documented.

-   **Trivy**: Ignored rules are placed in each project's `.trivyignore` file. Each entry must include the rule ID, affected resource, and a clear reason for the exception.
-   **Checkov**: Skips for Checkov are configured in each project's `.checkov.yml` file via a `skip-check` list.
-   **Documentation**: Every security exception, regardless of the tool, **must** include a documented reason explaining why the exception is necessary and what mitigating controls are in place.
