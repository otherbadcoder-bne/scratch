Creating a developer guide based on the provided context is a multi-step process. I'll break this down into a series of subtasks to ensure all requirements are met.
# Wiki.js Deployment Developer Guide

This guide provides instructions for developers working on the `wiki.js` Terraform project within this repository. It covers everything from local setup to deployment and architecture.

## 1. Introduction

This repository serves as a personal workspace for infrastructure-as-code experiments and small deployments. The `wiki.js/` directory contains a standalone Terraform project designed to deploy a Wiki.js instance on AWS. The architecture emphasizes simplicity, security, and cost-effectiveness.

## 2. Repository Structure

The `scratch` repository is structured as a collection of independent projects in subdirectories. The `wiki.js/` directory is one such project, acting as a root Terraform module.

-   `wiki.js/`: The root module for the Wiki.js Terraform deployment.
    -   `*.tf`: Terraform source files defining the AWS infrastructure.
    -   `tests/`: Contains Terraform test files (`*.tftest.hcl`).
    -   `docker-compose.yml`: Defines the Wiki.js and PostgreSQL services using Docker Compose.
    -   `user-data.sh.tftpl`: The EC2 user data script responsible for launching Docker containers.
    -   `.checkov.yml` / `.trivyignore`: Configuration files for security scanning exceptions.
-   `.github/workflows/`: Contains GitHub Actions CI workflows for pull requests.
-   `scripts/`: Holds helper scripts used by pre-commit hooks, such as `ai-review.sh` and `update-infracost.sh`.
-   `.pre-commit-config.yaml`: Defines the local pre-commit and pre-push hooks for code quality and security.
-   `AGENTS.md`: Provides high-level context about the repository's purpose and conventions for AI agents.

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

After installing the prerequisites, activate the Git hooks in your local repository clone:
```bash
pre-commit install                        # Installs commit-time hooks
pre-commit install --hook-type pre-push   # Installs the pre-push AI review hook
```

### 3.3. Authenticate Infracost

The `infracost` hook requires an API key to provide cost estimates for infrastructure changes:
```bash
infracost auth login
```

## 4. Environment Variables and Configuration

The `wiki.js` infrastructure is configured through variables defined in `wiki.js/variables.tf`.

-   `domain_name` (string, **required**): The domain name intended for the Wiki.js site (e.g., `wiki.example.com`).
-   `vpc_cidr` (string, optional): Specifies the CIDR block for the shared services VPC. Defaults to `"10.0.0.0/16"`.
-   `instance_type` (string, optional): Defines the EC2 instance type for the Wiki.js server. Defaults to `"t3.micro"`.
-   `environment` (string, optional): A name used for tagging AWS resources. Defaults to `"shared-services"`.
-   `schedule_enabled` (bool, optional): Controls whether the automatic stop/start schedule for the EC2 instance is enabled for cost savings. Defaults to `true`.

## 5. How to Run the Application Locally

The Wiki.js application and its PostgreSQL database run as Docker containers orchestrated by Docker Compose.

1.  Ensure Docker Desktop or Docker Engine is running on your machine.
2.  Navigate to the `wiki.js/` directory within the repository:
    ```bash
    cd wiki.js/
    ```
3.  Start the Wiki.js and PostgreSQL services:
    ```bash
    docker-compose up -d
    ```
    This command will build (if necessary) and start the containers in detached mode. The Wiki.js application will be accessible on `http://localhost:3000`.
4.  To stop the application:
    ```bash
    docker-compose down
    ```

## 6. How to Run Tests

This project utilizes Terraform's native testing capabilities.

To run the Terraform tests for the `wiki.js` module:
```bash
terraform -chdir=wiki.js test
```

## 7. Deployment Process

Deployment is managed through GitHub Actions workflows, primarily triggered by Pull Requests to the `main` branch.

-   **`terraform-ci.yml`**: This workflow runs on Pull Requests to `main`. It performs static analysis checks (format, validate, tflint, trivy, checkov, gitleaks) and generates a `terraform plan`, which is then posted as a comment on the Pull Request.
-   **`infracost.yml`**: This workflow also runs on Pull Requests to `main`. It calculates and posts an Infracost estimate comment on the Pull Request, providing insights into the cost impact of proposed changes.

AWS credentials for these CI/CD workflows are stored as GitHub Actions secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`).

## 8. Branching and Pull Request Conventions

-   The `main` branch is protected; direct commits are not allowed and are enforced by a pre-commit hook (`no-commit-to-branch`).
-   Development work should be carried out on the `develop` branch or dedicated feature branches.
-   All changes must be merged into `main` via a Pull Request.
-   GitHub Actions CI workflows automatically run on Pull Requests targeting `main` to ensure code quality and validate infrastructure changes.
-   Local pre-commit and pre-push hooks are used to enforce code standards and perform security scans before code is pushed to the remote repository. The `ai-review` pre-push hook provides an agentic review of changes.

## 9. Code Architecture Walkthrough (wiki.js)

The `wiki.js/` Terraform project is composed of several `.tf` files, each responsible for a specific part of the AWS infrastructure.

-   **`main.tf`**: Configures the required Terraform providers (AWS) and specifies default regions. It includes a special provider configuration for `us-east-1` for ACM certificates, which is a CloudFront requirement.
-   **`vpc.tf`**: Defines the Virtual Private Cloud (VPC), including public and private subnets across multiple Availability Zones, an Internet Gateway, route tables, and Network ACLs (NACLs) to control network traffic. It also sets up restricted default security groups and NACLs.
-   **`ec2.tf`**: Manages the EC2 instance where Wiki.js and PostgreSQL run. This file defines the IAM role and instance profile for SSM access, a security group to allow CloudFront traffic, and the EC2 instance itself, including its AMI (sourced from SSM Parameter Store), instance type, and user data script.
-   **`cloudfront.tf`**: Configures the AWS CloudFront distribution, which serves as the public entry point for Wiki.js. It defines the origin (the EC2 instance), cache behaviors, viewer protocol policy (redirects HTTP to HTTPS), and applies a custom response headers policy for security (HSTS, X-Frame-Options, etc.). It references an ACM certificate for TLS termination.
-   **`acm.tf`**: Handles the provisioning and validation of the SSL/TLS certificate from AWS Certificate Manager (ACM) in `us-east-1`, which is required for CloudFront.
-   **`scheduler.tf`**: Sets up an EventBridge Scheduler to automatically stop and start the EC2 instance outside of working hours (Mon-Fri 7am-7pm AEST) to optimize costs. This uses SSM Automation documents and an IAM role with necessary permissions.
-   **`outputs.tf`**: Exports important values from the deployed infrastructure, such as ACM validation records, CloudFront domain name and ID, EC2 instance ID, and VPC/subnet IDs. These outputs are useful for external configuration or integration.
-   **`user-data.sh.tftpl`**: A template file containing the shell script that the EC2 instance executes upon launch. This script is responsible for installing Docker and Docker Compose, and then starting the Wiki.js and PostgreSQL containers as defined in `docker-compose.yml`.
-   **`docker-compose.yml`**: Defines the Docker services for `wiki` (the Wiki.js application) and `database` (PostgreSQL), specifying their images, environment variables, port mappings, and volume mounts for data persistence.

## 10. Common Development Tasks

-   **Run all pre-commit hooks manually**: To execute all defined pre-commit hooks across all files without committing:
    ```bash
    pre-commit run --all-files
    ```
-   **Run a Terraform plan**: To preview the changes Terraform will make without applying them (from `wiki.js/` directory):
    ```bash
    terraform plan
    ```
-   **Apply Terraform changes**: To apply the planned infrastructure changes (from `wiki.js/` directory):
    ```bash
    terraform apply
    ```
-   **Access the EC2 instance via SSM Session Manager**: To get a shell prompt on the running Wiki.js EC2 instance without SSH keys:
    ```bash
    aws ssm start-session --target <EC2_INSTANCE_ID>
    ```
    (You can get the `<EC2_INSTANCE_ID>` from the `instance_id` output after `terraform apply`).
