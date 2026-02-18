## Performance Characteristics and Improvement Opportunities for Wiki.js Deployment

This document analyzes the current performance profile of the Wiki.js deployment and identifies areas for improvement, ranging from quick wins to longer-term architectural enhancements.

## Current Performance Profile

The current Wiki.js deployment utilizes a straightforward architecture primarily designed for cost-efficiency and ease of deployment for experimental use cases.

### Resource Allocations and Sizing

*   **EC2 Instance**: A single `t3.micro` instance is used for both the Wiki.js application and its PostgreSQL database. `t3.micro` instances are burstable, meaning they provide a baseline level of CPU performance with the ability to burst above it using CPU credits. This instance type is suitable for workloads with low-to-moderate CPU utilization, but sustained high usage can lead to CPU credit exhaustion and performance degradation.
*   **EBS Volume**: The EC2 instance's root block device is a `20GB gp3` volume. GP3 volumes offer a good balance of price and performance, with configurable IOPS and throughput. However, 20GB is a relatively small size, which could become a constraint as the Wiki.js content and database grow.
*   **Database**: PostgreSQL `15-alpine` runs as a Docker container on the same `t3.micro` instance, sharing resources with the Wiki.js application. Database performance is directly tied to the EC2 instance's capabilities and EBS volume performance.

### Caching and Content Delivery

*   **CloudFront Distribution**: A CloudFront distribution fronts the EC2 instance, providing TLS termination and applying security headers.
*   **Caching Policy**: The CloudFront distribution currently uses the `Managed-CachingDisabled` policy. This means that CloudFront performs no caching of content, effectively forwarding every request to the EC2 origin.

### Concurrency Model

*   The architecture is based on a single EC2 instance, running Wiki.js and PostgreSQL via Docker Compose. This design inherently limits concurrency and scalability, as there is no load balancing or horizontal scaling mechanism. All requests are handled by this single server.

### Timeouts and Availability

*   **Scheduled Stops/Starts**: The EC2 instance is configured to stop and start daily outside of working hours (Mon-Fri 7am-7pm AEST) using EventBridge Scheduler. While this is a cost-saving measure, it introduces periods of unavailability and cold start times.
*   **CloudFront Origin Protocol**: Traffic between CloudFront and the EC2 origin is configured as `http-only` on port 3000. This is a security risk (unencrypted traffic) and could also impact performance by preventing the use of more efficient protocols like HTTP/2 for origin fetches.

## Identified Bottlenecks or Risks

### Critical Bottleneck: CloudFront Caching Disabled
The most significant performance bottleneck is the disabled caching on the CloudFront distribution. Every user request, including those for static assets (images, CSS, JavaScript), is forwarded directly to the `t3.micro` EC2 instance. This drastically increases the load on the instance and results in higher latency for users who are geographically distant from the AWS region.

### Critical Risk: CloudFront Origin Breaks on EC2 Restart
As identified in `.ai/docs/bug-list.md`, the CloudFront distribution uses the dynamic public DNS name of the EC2 instance as its origin. When the scheduled stop/start occurs, the public DNS name changes, causing the CloudFront distribution to point to a non-existent or incorrect origin. This leads to complete service unavailability after each restart until the CloudFront distribution is manually updated or Terraform reapplied. While primarily an availability issue, zero availability means zero performance.

### Performance Risk: `t3.micro` CPU Credit Exhaustion
For anything beyond very light usage, the `t3.micro` instance running both the web application and its database is at high risk of CPU credit exhaustion. Once credits are depleted, the instance's CPU performance is throttled to its baseline, leading to slow response times and a poor user experience.

### Security & Performance Risk: `http-only` CloudFront Origin
The use of `http-only` for communication between CloudFront and the origin EC2 instance is a security risk. It also prevents CloudFront from leveraging more modern and efficient protocols (like HTTP/2) for origin communication, which could offer minor performance improvements.

### Scalability Limit: Single Instance Architecture
The single EC2 instance architecture presents a hard limit on scalability. As user traffic increases, this single server will become a bottleneck, unable to handle increased load, leading to degraded performance and potential outages.

## Specific Recommendations

### Quick Wins (High Impact, Low Effort)

1.  **Enable CloudFront Caching**:
    *   **Recommendation**: Configure CloudFront to cache static assets (e.g., images, CSS, JavaScript files) by creating appropriate cache behaviors and policies. For dynamic content, use a `CachingOptimized` or custom policy that respects `Cache-Control` headers from the origin.
    *   **Rationale**: This will significantly reduce the load on the EC2 instance, decrease latency for end-users, and improve overall responsiveness by serving content directly from CloudFront's edge locations.
    *   **Estimated Impact**: High.

2.  **Fix CloudFront Origin with Elastic IP**:
    *   **Recommendation**: Allocate an Elastic IP address and associate it with the EC2 instance. Update the CloudFront origin configuration to use this static Elastic IP address instead of the dynamic public DNS name.
    *   **Rationale**: This directly resolves the critical bug where CloudFront breaks after EC2 restarts, ensuring continuous availability of the application.
    *   **Estimated Impact**: Critical for availability, foundational for consistent performance.

3.  **Upgrade CloudFront to EC2 Origin to `https-only`**:
    *   **Recommendation**: Configure the Wiki.js application in Docker to serve HTTPS traffic (e.g., via a self-signed certificate if public trust is not required for internal CF-EC2 communication). Then, change the `origin_protocol_policy` in `wiki.js/cloudfront.tf` from `http-only` to `https-only` and specify the correct `https_port`.
    *   **Rationale**: Enhances security by encrypting traffic between CloudFront and the origin. Also allows for future performance optimizations that rely on HTTPS origin communication.
    *   **Estimated Impact**: Medium for security, minor for performance.

### Longer-Term Improvements (Higher Effort, Greater Scalability)

1.  **Upgrade EC2 Instance Type (Conditional)**:
    *   **Recommendation**: Monitor the `t3.micro` instance's CPU utilization and CPU credit balance. If credit exhaustion becomes a frequent issue under typical load, consider upgrading to a larger `t3` instance (e.g., `t3.small` or `t3.medium`) for a higher baseline CPU performance, or transition to a fixed-performance instance type (e.g., `m` or `c` series) if sustained high usage is expected.
    *   **Rationale**: Addresses potential CPU bottlenecks, ensuring the application has sufficient compute resources to operate smoothly.
    *   **Estimated Impact**: High if `t3.micro` is a bottleneck.

2.  **Migrate Database to AWS RDS**:
    *   **Recommendation**: Decouple the PostgreSQL database from the EC2 instance by migrating it to Amazon RDS (Relational Database Service).
    *   **Rationale**: RDS provides a managed database service, handling backups, patching, and scaling. It significantly improves database performance, reliability, and security compared to a self-managed Docker container on the application server. This also frees up resources on the EC2 instance for the Wiki.js application itself.
    *   **Estimated Impact**: High.

3.  **Implement Application Load Balancer (ALB) and Auto Scaling Group (ASG)**:
    *   **Recommendation**: Introduce an Application Load Balancer (ALB) in front of an Auto Scaling Group (ASG) containing the EC2 instance(s) running Wiki.js. CloudFront would then point to the ALB as its origin. Place the EC2 instances in private subnets.
    *   **Rationale**:
        *   **Scalability**: ASG automatically adds or removes instances based on demand, ensuring performance under varying loads.
        *   **High Availability**: Distributes traffic across multiple instances and availability zones, providing fault tolerance.
        *   **Static Origin**: The ALB provides a stable, static endpoint for CloudFront, robustly resolving the dynamic DNS issue.
        *   **Security**: Moving application servers to private subnets behind an ALB enhances network security.
    *   **Estimated Impact**: Very high, transforms the architecture into a scalable and highly available system.

## Infrastructure Sizing Observations

*   The current `t3.micro` instance type and `20GB gp3` EBS volume are typical choices for very small-scale or experimental deployments where cost is the primary driver.
*   For any production-like workload, or even a personal wiki that sees moderate use or content growth, this sizing is likely to be inadequate and will lead to performance issues and potential data storage constraints over time.
*   The absence of a NAT Gateway (as noted in `wiki.js/vpc.tf`) implies that private subnets currently have no outbound internet access. While stated as a cost-saving measure, this would prevent instances in private subnets from accessing package repositories or external APIs, which would need to be considered for any future expansion or maintenance of the EC2 instances.
