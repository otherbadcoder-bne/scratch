## Testing Wiki.js Terraform Deployment

This document provides an overview of the testing strategy for the `wiki.js` Terraform project, including current coverage, execution instructions, environment requirements, identified gaps, and recommendations for enhancing test confidence. It is intended for QA engineers and developers working with this infrastructure-as-code.

### How to Run Tests

The `wiki.js` project utilizes Terraform native testing, integrated with `pre-commit` hooks for automated execution during development.

**1. Using Pre-commit Hooks (Recommended for Developers):**

This method ensures tests run automatically before every commit, providing immediate feedback.

   a. **Install Pre-commit:**
      ```bash
      brew install pre-commit # macOS
      pip install pre-commit  # Windows/Linux
      ```

   b. **Activate Hooks:**
      Navigate to the repository root and activate the pre-commit hooks. The `terraform_test` hook is included in the commit-time hooks.
      ```bash
      pre-commit install
      ```

   c. **Run All Files (Optional):**
      To manually run all pre-commit hooks against all files in the repository:
      ```bash
      pre-commit run --all-files
      ```
      This will execute `terraform_test` alongside other linters and security checks.

**2. Running Terraform Native Tests Directly:**

For granular control or CI/CD environments, Terraform native tests can be run directly.

   a. **Navigate to the Project Directory:**
      ```bash
      cd wiki.js/
      ```

   b. **Execute Tests:**
      ```bash
      terraform test
      ```

### Test Environment Requirements

To run the existing Terraform tests, the following tools and configurations are required:

*   **Terraform CLI**: Version 1.5 or newer.
*   **Pre-commit Framework**: For automated execution via hooks.
*   **AWS CLI / Credentials**: Configured with valid AWS credentials and a default region (e.g., `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` environment variables, or a configured AWS profile). The `terraform_test` hook within `pre-commit` will attempt to provision resources, requiring these credentials.

### Current Test Coverage

The `wiki.js` project includes dedicated Terraform test files located in `wiki.js/tests/`. These tests validate specific aspects of the deployed AWS infrastructure.

#### `wiki.js/tests/cloudfront.tftest.hcl`

*   **Purpose**: Validates the configuration of the AWS CloudFront distribution and the associated ACM certificate.
*   **Validates**:
    *   That CloudFront is configured to redirect HTTP requests to HTTPS.
    *   That the CloudFront distribution allows all seven standard HTTP methods (GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE).
    *   That the CloudFront distribution uses the provided `domain_name` variable as an alias.
    *   That the CloudFront origin connects to the EC2 instance on TCP port 3000 using an HTTP-only protocol policy.
    *   That CloudFront enforces a minimum TLS protocol version of `TLSv1.2_2021`.
    *   Specific security headers are configured in the response headers policy:
        *   HTTP Strict Transport Security (HSTS) with a `max-age` of 1 year (31536000 seconds).
        *   `X-Frame-Options` set to `DENY`.
    *   The ACM certificate uses DNS validation.
    *   The ACM certificate's domain name matches the provided `domain_name` variable.

#### `wiki.js/tests/ec2.tftest.hcl`

*   **Purpose**: Validates the configuration of the AWS EC2 instance, its associated IAM role, and the EventBridge scheduler for instance management.
*   **Validates**:
    *   The EC2 instance type defaults to `t3.micro`.
    *   The EC2 instance enforces IMDSv2 (`http_tokens = "required"`).
    *   The EC2 instance's root block device is of type `gp3` and has a size of 20 GB.
    *   The EC2 IAM role has a valid assume role policy.
    *   The `AmazonSSMManagedInstanceCore` policy is attached to the EC2 IAM role.
    *   The EC2 security group allows inbound TCP traffic on port 3000.
    *   The absence of an SSH ingress rule in the EC2 security group.
    *   The EventBridge scheduler creates both stop and start schedules for the EC2 instance, verifying their cron expressions and the `Australia/Brisbane` timezone.

#### `wiki.js/tests/vpc.tftest.hcl`

*   **Purpose**: Validates the core AWS VPC configuration, including DNS settings and subnet arrangements.
*   **Validates**:
    *   The VPC has DNS support (`enable_dns_support`) and DNS hostnames (`enable_dns_hostnames`) enabled.
    *   The VPC CIDR block defaults to `10.0.0.0/16`.
    *   The creation of exactly three public subnets.
    *   The creation of exactly three private subnets.
    *   Public subnets are configured to auto-assign public IP addresses on launch.
    *   Private subnets are configured *not* to auto-assign public IP addresses on launch.
    *   Key resources (VPC, Internet Gateway) are tagged with the "environment" tag set to "shared-services".

### Gaps in Coverage

Based on the project's architectural description and existing tests, several areas lack explicit test coverage:

*   **CloudFront Origin Stability**: The tests do not verify that the CloudFront origin remains stable across EC2 instance restarts. The current architecture (public DNS name as origin with scheduled restarts) is a known critical bug where the public DNS name changes upon restart, breaking CloudFront.
*   **CloudFront to EC2 Traffic Encryption**: While the test asserts `http-only` for the CloudFront origin, it does not confirm or recommend HTTPS-only communication between CloudFront and the EC2 origin, which is a significant security concern.
*   **EC2 Egress Security Group Rules**: There are no tests to validate the outbound (egress) rules of the EC2 instance's security group. The current configuration is noted as a high-severity risk for being overly permissive.
*   **EBS Root Volume Encryption**: The encryption status of the EC2 instance's root block device is not tested. This is identified as a medium-severity risk.
*   **Network ACL Rules**: Only basic subnet creation is tested for the VPC. The Network ACLs (especially egress rules for public subnets) are not explicitly validated, leaving a medium-severity risk of overly permissive rules.
*   **IAM Least Privilege (Scheduler Role)**: While the EC2 IAM role is tested, the specific permissions for the EventBridge scheduler's IAM role are broadly described as a low-severity risk (`ec2:DescribeInstances` on `*` resources) but not strictly validated for least privilege.
*   **User Data Script**: The `user-data.sh.tftpl` script, which configures Docker and runs Wiki.js and PostgreSQL, is critical for application functionality but is not directly tested by Terraform's native tests.
*   **Terraform Output Values**: The project's `outputs.tf` defines important values, but these outputs are not validated by any existing tests.
*   **Application-Level Functionality**: Terraform tests validate infrastructure, but there are no integration or end-to-end tests to confirm the Wiki.js application itself is successfully deployed, running, and accessible after infrastructure provisioning.

### Recommendations for Additional Tests

To improve the confidence in the `wiki.js` Terraform deployment, the following tests are recommended:

1.  **CloudFront Origin Persistence Test**:
    *   Add a test to verify that the CloudFront distribution's origin uses a static endpoint (e.g., Elastic IP or Application Load Balancer DNS) for the EC2 instance when the scheduler is enabled, preventing downtime after instance restarts.
2.  **CloudFront Origin HTTPS Enforcement Test**:
    *   Introduce a test to assert that the CloudFront `custom_origin_config` uses `https-only` for `origin_protocol_policy`, once the EC2 instance is configured to handle HTTPS.
3.  **EC2 Security Group Egress Restriction Test**:
    *   Add tests to confirm that the EC2 instance's security group egress rules are limited to only essential outbound traffic (e.g., TCP 443 for external APIs, UDP 53 for DNS).
4.  **EBS Volume Encryption Test**:
    *   Create a test to verify that the EC2 instance's root block device has `encrypted = true`.
5.  **Network ACL Egress Policy Test**:
    *   Implement tests for public subnet Network ACLs to ensure egress rules are restrictive, allowing only necessary outbound traffic and return traffic for established connections.
6.  **Granular IAM Permission Test**:
    *   If possible, add a test to verify that the EventBridge scheduler's IAM role permissions are scoped to the specific EC2 instance ARN rather than wildcard resources for `ec2:DescribeInstances` actions.
7.  **Output Value Validation Test**:
    *   Add tests to assert that critical output values (e.g., CloudFront distribution domain name, any exposed endpoints) from `outputs.tf` are correctly generated and contain expected values.
8.  **Application Health Integration Test (High-Level Recommendation)**:
    *   While not a Terraform native test, consider adding an integration test using a tool like Terratest or an external monitoring system to perform an HTTP GET request against the deployed Wiki.js application's public URL and assert a successful HTTP 200 response. This would validate the full stack, including the `user-data.sh.tftpl` script and Docker Compose setup.
