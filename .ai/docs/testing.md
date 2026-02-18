# Wiki.js Terraform Project: Testing Guide

This document serves as a comprehensive guide for developers and QA engineers involved in testing the `wiki.js` Terraform deployment. It covers existing test coverage, execution methods, environment requirements, and recommendations for improving test confidence.

## 1. Introduction

The `wiki.js/` project deploys a Wiki.js instance on AWS using Terraform. To ensure the reliability, security, and correct configuration of this infrastructure, a suite of Terraform native tests is included. These tests validate various aspects of the deployed AWS resources.

## 2. Test Environment Requirements

To run the existing Terraform tests locally, the following prerequisites must be met:

### 2.1. Tool Installation

The following tools are required and must be installed on your local system:

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

### 2.2. AWS Credentials

The `terraform_test` pre-commit hook, and direct `terraform test` commands, require valid AWS credentials configured locally to perform plan assertions against AWS APIs. These credentials should have permissions to perform `terraform plan` operations in the target AWS account.

### 2.3. Pre-commit Hooks Activation

Although `terraform_test` is a pre-commit hook, it's recommended to have all hooks installed for a complete development experience.

```bash
pre-commit install                        # Installs commit-time hooks
pre-commit install --hook-type pre-push   # Installs the pre-push AI review hook
```

### 2.4. Infracost Authentication (for general development workflow)

The `infracost` hook, part of the pre-commit suite, requires authentication:

```bash
infracost auth login
```

## 3. How to Run Existing Tests

The `wiki.js` project utilizes Terraform's native testing framework, integrated into the pre-commit hooks.

### 3.1. Via Pre-commit Hook

The primary method for running tests is through the `terraform_test` pre-commit hook. This hook automatically executes when `git commit` is run.

```bash
git commit -m "feat: my changes"
```

If any Terraform test assertions fail, the commit will be blocked.

### 3.2. Manually (against all files)

To run all commit-time hooks, including `terraform_test`, against all files in the repository at any time:

```bash
pre-commit run --all-files
```

### 3.3. Directly via Terraform CLI

To run the Terraform native tests specifically for the `wiki.js/` module using the Terraform CLI:

```bash
cd wiki.js/
terraform test
```

## 4. Description of Test Files and Validations

The `wiki.js/tests/` directory contains the Terraform native test files, each focusing on specific infrastructure components.

### 4.1. `cloudfront.tftest.hcl`

This test file validates the configuration of the AWS CloudFront distribution and the ACM certificate.

Validations include:
*   CloudFront redirects HTTP to HTTPS.
*   CloudFront allows all 7 HTTP methods (GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE).
*   CloudFront uses the provided `domain_name` as an alias.
*   CloudFront origin connects to port 3000 over HTTP-only (TLS terminates at CloudFront).
*   CloudFront enforces a minimum TLS 1.2 protocol version.
*   CloudFront applies a response headers policy with HSTS `max-age` of 1 year and X-Frame-Options set to `DENY`.
*   ACM certificate uses DNS validation.
*   ACM certificate is issued for the provided `domain_name`.

### 4.2. `ec2.tftest.hcl`

This test file validates the configuration of the AWS EC2 instance, its associated IAM role, SSM policy attachment, security group rules, and the EventBridge scheduler.

Validations include:
*   EC2 instance type defaults to `t3.micro`.
*   EC2 instance enforces IMDSv2 (`http_tokens = required`, `http_endpoint = enabled`).
*   EC2 root volume uses `gp3` type and a size of 20 GB.
*   EC2's IAM role has a valid assume role policy.
*   `AmazonSSMManagedInstanceCore` policy is attached to the EC2 IAM role.
*   Security group allows TCP ingress on port 3000.
*   No SSH ingress rule is present in the security group.
*   EventBridge scheduler creates stop (`cron(0 19 ? * MON-FRI *)`) and start (`cron(0 5 ? * MON-FRI *)`) schedules.
*   Schedules use the `Australia/Brisbane` timezone.

### 4.3. `vpc.tftest.hcl`

This test file validates the core AWS VPC networking components.

Validations include:
*   VPC has DNS support and DNS hostnames enabled.
*   VPC CIDR block defaults to `10.0.0.0/16`.
*   Three public subnets are created.
*   Three private subnets are created.
*   Public subnets auto-assign public IPs.
*   Private subnets do not auto-assign public IPs.
*   VPC and Internet Gateway resources are tagged with the `environment` name.

## 5. Gaps in Test Coverage

While the existing tests cover fundamental aspects of the infrastructure, several critical areas currently lack dedicated test coverage, posing potential risks.

*   **CloudFront Origin Immutability (Critical Bug):** The current `cloudfront.tftest.hcl` confirms the origin connects to port 3000 with HTTP-only. However, there is no test to address the critical bug where the CloudFront origin breaks when the EC2 instance restarts and its public DNS name changes.
*   **Encrypted Traffic Between CloudFront and EC2 (High Risk):** The current tests explicitly assert `http-only` for the origin protocol. There are no tests to enforce or verify a secure `https-only` connection between CloudFront and the EC2 origin, leaving this high-severity risk unmitigated by tests.
*   **EC2 Egress Security (High Risk):** The `ec2.tftest.hcl` focuses on ingress rules. There are no tests to validate or restrict the EC2 instance's outbound traffic, which is currently overly permissive (`0.0.0.0/0`), as highlighted in the codebase review.
*   **EBS Root Volume Encryption (Medium Risk):** While `ec2.tftest.hcl` verifies the volume type and size, it lacks an assertion to ensure the EC2 root block device is encrypted, leaving data at rest vulnerable.
*   **Public Network ACL Egress (Medium Risk):** The `vpc.tftest.hcl` tests VPC basics but does not include assertions for the Network ACL's egress rules, which are currently overly permissive in the public subnets.
*   **IAM Role Least Privilege (Low Risk):** The `ec2.tftest.hcl` confirms IAM role creation and SSM policy attachment. However, there are no specific tests to ensure that the `ec2:DescribeInstances` and `ec2:DescribeInstanceStatus` permissions for the scheduler IAM role are scoped to the least privilege possible (e.g., to the specific instance ARN).
*   **Docker Compose & Application Logic:** There are no infrastructure tests that validate the functionality or deployment of Docker Compose, Wiki.js, or PostgreSQL containers on the EC2 instance. The `user-data.sh.tftpl` script, which orchestrates these, is also not covered by tests.
*   **Terraform Outputs:** No tests explicitly validate the correctness or existence of Terraform output values (e.g., CloudFront domain name, EC2 public IP).
*   **Full Resource Tagging:** While some resources are tested for tagging, comprehensive coverage for tagging across all created AWS resources is not present.
*   **Security Configuration (Trivy/Checkov):** Although `Trivy` and `Checkov` are run as pre-commit hooks, there are no `.tftest.hcl` files that validate the configuration of these tools or the justifications for any security exceptions (`.trivyignore`, `.checkov.yml`).

## 6. Recommendations for Additional Tests

To improve the confidence in the `wiki.js` deployment, the following additional tests are recommended:

*   **CloudFront Origin Static Endpoint:**
    *   Add a test to verify that the CloudFront distribution is configured to use a static origin (e.g., an Elastic IP or an ALB DNS name) that persists across EC2 restarts, rather than a dynamic public DNS.
*   **Secure CloudFront to EC2 Origin:**
    *   Introduce a test to assert that the `origin_protocol_policy` for the CloudFront origin is set to `https-only`, ensuring encrypted traffic between CloudFront and the EC2 instance. This requires configuring Wiki.js to serve HTTPS directly or via a local proxy.
*   **Restricted EC2 Egress Rules:**
    *   Add tests to the `ec2.tftest.hcl` to ensure that the EC2 instance's security group egress rules are limited to only necessary outbound traffic (e.g., HTTPS to common ports, DNS).
*   **EBS Root Volume Encryption:**
    *   Add an assertion to `ec2.tftest.hcl` to verify that the `root_block_device` for the EC2 instance has `encrypted = true`.
*   **Restrict Public Network ACL Egress:**
    *   Add tests to `vpc.tftest.hcl` to ensure the public network ACL egress rules are tightened to allow only return traffic for established connections.
*   **Scoped IAM Permissions:**
    *   Refine the IAM role tests in `ec2.tftest.hcl` (or create a new test file) to verify that permissions like `ec2:DescribeInstances` are scoped to the specific resource ARN where possible.
*   **User Data Script Validation (Sh-lint or similar):**
    *   While direct `tftest.hcl` for shell scripts is challenging, consider integrating a linter for `user-data.sh.tftpl` into pre-commit hooks to catch syntax errors or basic logical flaws.
*   **Terraform Output Validation:**
    *   Create a new test file, `outputs.tftest.hcl`, to assert that key Terraform outputs (e.g., `cloudfront_domain_name`, `ec2_instance_id`) exist and match expected patterns.
*   **Comprehensive Resource Tagging:**
    *   Expand tagging tests in `vpc.tftest.hcl` and add similar assertions to `cloudfront.tftest.hcl` and `ec2.tftest.hcl` to ensure all relevant AWS resources are consistently tagged with the `environment` variable.
*   **Security Scanner Configuration:**
    *   Consider adding tests (if feasible with Terraform testing) to validate the presence and format of `.trivyignore` and `.checkov.yml` files within the `wiki.js/` directory, ensuring that security exception documentation is present.
