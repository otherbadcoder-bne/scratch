# Terraform Test Strategy: Wiki.js

This document outlines the test coverage, environment requirements, and execution strategy for the Wiki.js Terraform project. The tests are designed to validate the configuration of the AWS infrastructure as defined in the Terraform code, ensuring it aligns with architectural and security requirements.

## Overview

The project utilizes native Terraform tests (`.tftest.hcl`) to assert the expected state of resources from a `terraform plan`. This approach validates resource attributes, connections, and security configurations before any infrastructure is deployed.

Tests are integrated into the pre-commit framework, running automatically upon `git commit`.

## Test Environment Requirements

To execute the tests, the following are required:
- **Terraform CLI**: The tests are run using the `terraform test` command.
- **AWS Credentials**: While the tests run against the plan and do not deploy resources, valid AWS credentials are required for the Terraform provider to initialize and generate the plan.

## How to Run Tests

Tests are executed automatically as a `pre-commit` hook. They can also be run manually.

Navigate to the project directory and run the following command:
```bash
cd wiki.js/
terraform test
```

## Current Test Coverage

The test suite is organized into files that correspond to the logical components of the infrastructure: VPC, EC2, and CloudFront.

### `tests/vpc.tftest.hcl`

This file validates the networking foundation of the project.

**Key Validations:**
- **VPC Configuration**:
  - Asserts that the VPC has `enable_dns_support` and `enable_dns_hostnames` set to `true`.
  - Confirms the default VPC CIDR block is `10.0.0.0/16`.
- **Subnet Structure**:
  - Verifies that exactly 3 public and 3 private subnets are created.
  - Ensures `map_public_ip_on_launch` is `true` for public subnets and `false` for private subnets.
- **Resource Tagging**:
  - Checks that the VPC and Internet Gateway are tagged with `environment = shared-services`.

### `tests/ec2.tftest.hcl`

This file focuses on the EC2 instance, its security posture, and associated IAM roles.

**Key Validations:**
- **Instance Configuration**:
  - Verifies the default instance type is `t3.micro`.
  - Confirms the root EBS volume is a 20 GB `gp3` volume.
- **Security**:
  - Enforces IMDSv2 by asserting `http_tokens` is set to `required`.
  - Confirms the `AmazonSSMManagedInstanceCore` policy is attached to the instance's IAM role, enabling SSM Session Manager access.
  - Asserts that the security group allows inbound TCP traffic on port 3000.
  - Explicitly asserts that there is **no** ingress rule for port 22 (SSH), enforcing a no-SSH policy.
- **IAM**:
  - Validates that the instance's IAM role has a valid assume role policy for the EC2 service.
- **Scheduler**:
  - If `schedule_enabled` is true, verifies that AWS Scheduler is configured to stop and start the instance on a weekday schedule (`MON-FRI`).
  - Asserts the schedules use the `Australia/Brisbane` timezone.

### `tests/cloudfront.tftest.hcl`

This file validates the CloudFront distribution, its origin configuration, and security headers.

**Key Validations:**
- **Traffic and TLS**:
  - Ensures the viewer protocol policy is set to `redirect-to-https`.
  - Verifies the minimum TLS version is `TLSv1.2_2021`.
- **Domain and Origin**:
  - Confirms the distribution uses the correct custom domain name.
  - Asserts the origin connects to the EC2 instance over `http-only` on port `3000`.
- **HTTP Methods**:
  - Asserts that all 7 HTTP methods (`GET`, `HEAD`, `OPTIONS`, `PUT`, `POST`, `PATCH`, `DELETE`) are allowed, which is necessary for Wiki.js functionality.
- **Security Headers**:
  - Validates that a response headers policy is attached.
  - Checks that the HSTS `max-age` is set to one year.
  - Ensures the `X-Frame-Options` header is set to `DENY`.
- **ACM Certificate**:
  - Confirms the ACM certificate uses `DNS` validation and is issued for the correct domain.

## Gaps in Coverage and Recommendations

While the current tests provide good coverage for resource attributes, several areas could be improved to increase confidence in the deployment.

### 1. VPC Routing
- **Gap**: The tests confirm the existence of subnets and an Internet Gateway but do not validate the route tables. There is no assertion that public subnets have a route to the IGW or that private subnets have a route to a NAT Gateway for outbound access.
- **Recommendation**: Add tests to assert that:
    - The public route table has a `0.0.0.0/0` route pointing to the Internet Gateway.
    - The private route table has a `0.0.0.0/0` route pointing to a NAT Gateway.
    - Subnets are correctly associated with their respective route tables.

### 2. IAM Policy Granularity
- **Gap**: The EC2 tests confirm the attachment of the AWS-managed `AmazonSSMManagedInstanceCore` policy but do not inspect the permissions of other IAM policies. The IAM role for the EventBridge Scheduler is also not tested.
- **Recommendation**:
    - Add a test to ensure the scheduler's IAM role has `ec2:StartInstances` and `ec2:StopInstances` permissions and that these permissions are scoped to the specific Wiki.js instance ARN.
    - If any custom IAM policies are added, create tests to validate their JSON content and ensure they adhere to the principle of least privilege.

### 3. Data Persistence and State
- **Gap**: The current test suite has no visibility into the Docker Compose setup defined in `user-data.sh.tftpl`. The most significant risk is the lack of validation for data persistence for the PostgreSQL database.
- **Recommendation**: While native Terraform tests cannot inspect the instance's runtime state, they can validate the configuration that enables it.
    - Add a test to assert that an EBS volume is created and attached to the EC2 instance for database persistence.
    - Add a test to validate that the `user-data.sh.tftpl` template file is correctly referenced and rendered in the EC2 instance configuration.

### 4. CloudFront Caching
- **Gap**: The tests validate the protocol policy and allowed methods but do not assert the caching behavior. The default caching policy might not be optimal for a dynamic application like Wiki.js.
- **Recommendation**: Add tests to assert that a specific cache policy is used, and validate key settings like TTLs and which headers, cookies, and query strings are forwarded to the origin.
