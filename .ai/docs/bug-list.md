## Codebase Review: Bugs, Risks, and Quality

This document outlines identified bugs, security risks, and code quality issues within the `wiki.js` Terraform project and associated scripts. Findings are grouped by severity, with recommended fixes provided for each.

### ## Critical Severity

#### **[BUG] CloudFront Origin Breaks When EC2 Instance Restarts**

*   **Description**: The CloudFront distribution (`aws_cloudfront_distribution.wiki`) uses the EC2 instance's public DNS name (`aws_instance.wiki.public_dns`) as its origin. The project also includes a scheduler (`aws_scheduler_schedule.wiki_stop`/`_start`) that stops and starts the instance daily. When an EC2 instance is stopped and started, its public DNS name changes, but the CloudFront distribution is not updated. This will cause the site to become unavailable after the first scheduled restart.
*   **Affected Files**:
    *   `wiki.js/cloudfront.tf` (line 72)
    *   `wiki.js/scheduler.tf` (lines 80 and 99)
*   **Severity**: Critical
*   **Recommended Fix**:
    1.  **Short-term**: Associate an Elastic IP address with the EC2 instance and use the Elastic IP as the CloudFront origin address. This provides a static endpoint that survives restarts.
    2.  **Long-term**: Re-architect to place the EC2 instance in a private subnet and front it with an Application Load Balancer (ALB). Set the ALB as the origin for CloudFront. This is more secure, scalable, and robust.

### ## High Severity

#### **[RISK] Unencrypted Traffic Between CloudFront and EC2 Origin**

*   **Description**: The CloudFront origin is configured with `origin_protocol_policy = "http-only"`. This means all traffic between CloudFront and the backend EC2 instance is sent over unencrypted HTTP. An attacker on the network could potentially intercept and read sensitive data, such as user sessions or content.
*   **Affected File**: `wiki.js/cloudfront.tf` (line 78)
*   **Severity**: High
*   **Recommended Fix**:
    1.  Configure the Wiki.js application (running in Docker) to handle HTTPS traffic on a specific port (e.g., 3001). This may involve generating a self-signed certificate for the instance.
    2.  Update the `custom_origin_config` block in `cloudfront.tf` to use `origin_protocol_policy = "https-only"` and set the `https_port`.
    3.  Ensure the EC2 security group allows inbound traffic from CloudFront on the new HTTPS port.

#### **[RISK] Unrestricted Outbound Traffic from EC2 Instance**

*   **Description**: The EC2 instance's security group (`aws_vpc_security_group_egress_rule.all`) allows all outbound traffic to any destination on any port (`0.0.0.0/0` via protocol `-1`). If the instance were compromised, an attacker could use it to exfiltrate data to any server on the internet or use it to launch attacks against other systems.
*   **Affected File**: `wiki.js/ec2.tf` (line 69)
*   **Severity**: High
*   **Recommended Fix**: Follow the principle of least privilege. Restrict egress traffic to only what is necessary. For a standard web server, this typically includes:
    *   HTTPS (port 443) to required external services (e.g., package repositories, external APIs).
    *   DNS (port 53) to the VPC resolver.
    *   Consider using a NAT Gateway in a private subnet for more controlled egress if external access is needed.

### ## Medium Severity

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

#### **[RISK] Overly Permissive Public Network ACL**

*   **Description**: The Network ACL for the public subnets (`aws_network_acl.public`) allows all outbound traffic (`egress` rule 100). While NACLs are stateless, this is still overly permissive and reduces the effectiveness of defense-in-depth. A more restrictive ruleset should be applied.
*   **Affected File**: `wiki.js/vpc.tf` (line 217)
*   **Severity**: Medium
*   **Recommended Fix**: Tighten the egress rule to only allow return traffic for established connections. This typically means allowing outbound TCP traffic on ephemeral ports `1024-65535`. Deny all other egress traffic unless explicitly required.

### ## Low Severity

#### **[RISK] IAM Role with Broad Describe Permission**

*   **Description**: The IAM role for the EventBridge Scheduler (`aws_iam_role_policy.scheduler`) grants `ec2:DescribeInstances` and `ec2:DescribeInstanceStatus` permissions on all resources (`Resource = "*"`). While some AWS actions require a wildcard resource, these specific permissions could potentially be scoped to the ARN of the `aws_instance.wiki` resource.
*   **Affected File**: `wiki.js/scheduler.tf` (line 70)
*   **Severity**: Low
*   **Recommended Fix**: Attempt to scope the `EC2Describe` statement to the specific instance ARN. If the API action requires a wildcard, document this with a comment.
    ```json
    {
      "Sid": "EC2Describe",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus"
      ],
      "Resource": "${aws_instance.wiki.arn}" // Change from "*"
    }
    ```

### ## Technical Debt and Code Quality Patterns

This section addresses architectural choices and recurring patterns that, while not immediate bugs, increase risk and maintenance overhead.

*   **Architectural Model**: The core architecture (a single EC2 instance in a public subnet) is brittle and deviates from modern best practices. The reliance on a public IP, unencrypted origin traffic, and direct exposure (albeit firewalled) to the internet creates unnecessary risk and operational fragility. The documented skips for WAF, access logging, and failover confirm that this is a cost-optimized but high-risk setup. The project would be significantly more robust and secure by adopting an ALB + private EC2 instance model, or by moving to a container-based service like ECS/Fargate.

*   **Over-reliance on Suppressions**: The codebase has numerous `checkov:skip` and `trivy:ignore` comments. While documenting exceptions is good practice, the volume of suppressions suggests a pattern of prioritizing cost-savings and convenience over security. This creates a "culture of exceptions" where security best practices are not the default. Findings related to encryption, logging, and WAF should be addressed rather than perpetually ignored.

*   **Confusing Script Naming**: The repository contains two identically named scripts: `scripts/validate-iam-policies.sh` and `wiki.js/scripts/validate-iam-policies.sh`. This is confusing for developers. The root-level script acts as a dispatcher, while the project-level script performs the actual validation. They should be renamed to clarify their distinct purposes (e.g., `run-all-iam-validations.sh` and `validate-iam-plan.sh`).

*   **Script Portability**: The use of `mktemp /tmp/ai-review-prompt.XXXXXX` in `ai-review.sh` is not fully portable across all Unix-like systems. Using a relative path or a more compatible `mktemp` syntax would improve robustness.
