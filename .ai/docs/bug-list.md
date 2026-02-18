## Codebase Review: Bugs, Risks, and Quality

This document outlines identified bugs, security risks, and code quality issues within the `wiki.js` Terraform project and associated scripts. Findings are grouped by severity, with recommended fixes provided for each.

### Critical Severity

#### **[BUG] CloudFront Origin Breaks When EC2 Instance Restarts**
*   **Description**: The CloudFront distribution (`aws_cloudfront_distribution.wiki`) uses the EC2 instance's public DNS name (`aws_instance.wiki.public_dns`) as its origin. The project also includes a scheduler (`aws_scheduler_schedule.wiki_stop`/`_start`) that stops and starts the instance daily. When an EC2 instance is stopped and started, its public DNS name changes, but the CloudFront distribution is not updated. This will cause the site to become unavailable after the first scheduled restart.
*   **Affected Files**:
    *   `wiki.js/cloudfront.tf` (line 72)
    *   `wiki.js/scheduler.tf` (lines 80 and 99)
*   **Severity**: Critical
*   **Recommended Fix**:
    1.  **Short-term**: Associate an Elastic IP address with the EC2 instance and use the Elastic IP as the CloudFront origin address. This provides a static endpoint that survives restarts.
    2.  **Long-term**: Re-architect to place the EC2 instance in a private subnet and front it with an Application Load Balancer (ALB). Set the ALB as the origin for CloudFront. This is more secure, scalable, and robust.

### High Severity

#### **[RISK] Unencrypted Traffic Between CloudFront and EC2 Origin**
*   **Description**: The CloudFront origin is configured with `origin_protocol_policy = "http-only"`. This means all traffic between CloudFront and the backend EC2 instance is sent over unencrypted HTTP. An attacker on the network could potentially intercept and read sensitive data, such as user sessions or content.
*   **Affected File**: `wiki.js/cloudfront.tf` (line 78)
*   **Severity**: High
*   **Recommended Fix**:
    1.  Configure the Wiki.js application (running in Docker) to handle HTTPS traffic on a specific port (e.g., 3001). This may involve generating a self-signed certificate for the instance or using a reverse proxy like Nginx on the EC2 to handle TLS locally.
    2.  Update the `custom_origin_config` block in `cloudfront.tf` to use `origin_protocol_policy = "https-only"` and set the `https_port`.
    3.  Ensure the EC2 security group allows inbound traffic from CloudFront on the new HTTPS port.

#### **[RISK] Unrestricted Outbound Traffic from EC2 Instance**
*   **Description**: The EC2 instance's security group (`aws_vpc_security_group_egress_rule.all`) allows all outbound traffic to any destination on any port (`0.0.0.0/0` via protocol `-1`). If the instance were compromised, an attacker could use it to exfiltrate data to any server on the internet or use it to launch attacks against other systems. The `trivy:ignore` comment is not a valid justification for this broad permission.
*   **Affected File**: `wiki.js/ec2.tf` (line 69)
*   **Severity**: High
*   **Recommended Fix**: Follow the principle of least privilege. Restrict egress traffic to only what is necessary. For a standard web server, this typically includes:
    *   HTTPS (port 443) to required external services (e.g., package repositories for updates, external APIs).
    *   DNS (port 53) to the VPC resolver.
    *   Consider using a NAT Gateway in a private subnet for more controlled egress if external access is needed.

### Medium Severity

#### **[RISK] EBS Root Volume is Not Encrypted**
*   **Description**: The EC2 instance's root block device is not configured for encryption (`#trivy:ignore:AWS-0131`). Data at rest on the volume is unencrypted. If the volume were ever detached or the underlying physical hardware compromised, the data could be read. The provided justification ("harder to work with") is not a valid reason to bypass a fundamental security control.
*   **Affected File**: `wiki.js/ec2.tf` (line 90)
*   **Severity**: Medium
*   **Recommended Fix**: Enable EBS encryption on the `root_block_device`. This can be done by adding `encrypted = true` to the block. The performance impact is negligible and it adds a critical layer of defense-in-depth.
    ```hcl
    resource "aws_instance" "wiki" {
      # ...
      root_block_device {
        volume_size = 20
        volume_type = "gp3"
        encrypted   = true // Add this line
      }
      # ...
    }
    ```

#### **[RISK] Overly Permissive Public Network ACL Egress Rule**
*   **Description**: The Network ACL for the public subnets (`aws_network_acl.public`) allows all outbound traffic (`egress` rule 100). While NACLs are stateless and security groups typically handle stateful filtering, this is still overly permissive and reduces the effectiveness of defense-in-depth by allowing any outbound traffic regardless of the EC2 instance's security group.
*   **Affected File**: `wiki.js/vpc.tf` (line 217)
*   **Severity**: Medium
*   **Recommended Fix**: Tighten the egress rule to only allow return traffic for established connections. This typically means allowing outbound TCP traffic on ephemeral ports `1024-65535` and DNS (port 53). Deny all other egress traffic unless explicitly required.

### Low Severity

#### **[RISK] IAM Role with Broad Describe Permission for Scheduler**
*   **Description**: The IAM role for the EventBridge Scheduler (`aws_iam_role_policy.scheduler`) grants `ec2:DescribeInstances` and `ec2:DescribeInstanceStatus` permissions on all resources (`Resource = "*"`) for the `EC2Describe` statement. While some AWS actions require a wildcard resource, these specific permissions could potentially be scoped to the ARN of the `aws_instance.wiki` resource, following the principle of least privilege.
*   **Affected File**: `wiki.js/scheduler.tf` (line 70)
*   **Severity**: Low
*   **Recommended Fix**: Attempt to scope the `EC2Describe` statement to the specific instance ARN, or at least to instances with specific tags. If the API action truly requires a wildcard, add an explicit comment documenting this constraint.

#### **[CODE QUALITY] Hardcoded `us-east-1` Region for ACM Provider**
*   **Description**: The `us_east_1` AWS provider is explicitly configured with `region = "us-east-1"` in `wiki.js/main.tf`. While ACM certificates for CloudFront generally require `us-east-1`, using a variable for the region would make the configuration more flexible if this requirement ever changes or if other global services are introduced that have similar regional constraints.
*   **Affected File**: `wiki.js/main.tf` (line 16)
*   **Severity**: Low
*   **Recommended Fix**: Introduce a new variable, e.g., `acm_region`, with a default of `"us-east-1"`, and use this variable in the `us_east_1` provider block. This allows for easier modification if regional requirements change in the future.

### Technical Debt and Code Quality Patterns

#### **1. Centralized Security Scanning Configuration**
*   **Observation**: Trivy and Checkov skips/ignores are defined inline in `.tf` files (e.g., `cloudfront.tf`, `ec2.tf`, `vpc.tf`) and in project-specific files like `.checkov.yml` and `.trivyignore`.
*   **Technical Debt**: While documented, the scattering of these exceptions can make auditing and managing security baselines more complex. It's easy to miss an exception or for justifications to become stale.
*   **Recommendation**: Consolidate security scanning exceptions where possible. For Checkov, leverage the `.checkov.yml` files as much as possible for `skip-check` entries with comprehensive justifications. For Trivy, ensure `.trivyignore` is well-maintained. Consider a central repository-level documentation for *all* security exceptions with their latest justifications.

#### **2. AMI Sourcing and Management**
*   **Observation**: The EC2 instance uses the latest Amazon Linux 2023 AMI via SSM Parameter Store (`data "aws_ssm_parameter" "al2023_ami"`).
*   **Technical Debt**: While good for always getting the latest security patches, this introduces potential for unexpected breaking changes if a new AMI version introduces a compatibility issue with Docker or Wiki.js, especially during an automated deployment.
*   **Recommendation**: Implement an AMI bake process (e.g., using Packer) to create custom AMIs that include Docker and any other base dependencies pre-installed and tested with Wiki.js. This provides a more controlled and stable base image, allowing for deliberate updates. Alternatively, specify a version constraint in the SSM parameter lookup or pin to a specific AMI ID temporarily for stability.

#### **3. Lack of Logging/Monitoring for EC2 Host**
*   **Observation**: The EC2 instance does not explicitly configure CloudWatch agent for host-level metrics or log collection (e.g., Docker logs, system logs). Checkov skips related to detailed monitoring (`CKV_AWS_126`) are present.
*   **Technical Debt**: Limited visibility into the health and performance of the EC2 host and Docker containers makes troubleshooting difficult and proactive issue detection impossible.
*   **Recommendation**: Implement CloudWatch Agent to collect system metrics (CPU, memory, disk, network) and push Docker container logs (Wiki.js, PostgreSQL) to CloudWatch Logs. This is crucial for operational insights and debugging.

#### **4. Inline `user_data` Scripting with File Content**
*   **Observation**: The `user_data` for the EC2 instance uses `templatefile` to embed the `docker-compose.yml` directly into the startup script.
*   **Technical Debt**: This approach can make the `user_data` script large and harder to debug, especially if the `docker-compose.yml` becomes complex. It also couples the Terraform configuration tightly to the Docker Compose file.
*   **Recommendation**: For more complex `user_data`, consider using a dedicated configuration management tool (e.g., Ansible Local, cloud-init modules) or a simpler shell script that downloads the `docker-compose.yml` from S3 or a private Git repository at boot time.

#### **5. Terraform Version Pinning for Providers and Terraform Itself**
*   **Observation**: The `main.tf` file uses `required_version = ">= 1.5"` and `aws = "~> 5.0"`.
*   **Technical Debt**: While `~> 5.0` is good, a more explicit minor version or patch version constraint (e.g., `~> 5.10.0` or `5.x.x`) for the AWS provider can prevent unexpected changes from newer minor versions. Similarly, for Terraform itself, `">= 1.5"` is very broad.
*   **Recommendation**: Tighten version constraints to ensure greater predictability in Terraform runs. For example, `required_version = "~> 1.5.0"` and `version = "~> 5.10"` (or the specific version currently in use).

#### **6. Use of `count` for Subnets**
*   **Observation**: Public and private subnets are created using `count = 3` and `data.aws_availability_zones.available.names[count.index]`.
*   **Technical Debt**: While functional, managing resources with `count` can sometimes lead to more complex state management and resource addressing, especially when individual subnets need unique configurations or are removed.
*   **Recommendation**: For a small, fixed number of subnets, `for_each` with a map of availability zones or CIDR blocks can sometimes lead to more readable and maintainable code, as each resource gets a distinct key. However, for dynamic scaling of subnets, `count` remains appropriate. This is a minor point for consideration.
