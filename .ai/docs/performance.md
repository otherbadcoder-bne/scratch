## Performance & Optimization Analysis: Wiki.js Deployment

This document analyzes the performance characteristics of the Wiki.js Terraform deployment, identifies potential bottlenecks, and provides recommendations for improvement. The analysis is based on the infrastructure defined in the repository's source files.

### Current Performance Profile

The architecture is designed for cost-efficiency, prioritizing low operational expense over high performance and availability.

#### Compute & Storage
*   **Instance Type**: The application and its database run on a single `t3.micro` EC2 instance (`variables.tf`). This instance class provides 2 vCPUs and 1 GiB of RAM on a burstable performance model.
*   **Shared Resources**: Both the Wiki.js application (Node.js) and the PostgreSQL database run as containers on the same host (`docker-compose.yml`). They compete for the same limited CPU, memory, and I/O resources.
*   **Storage**: A 20GB `gp3` EBS volume is used for the root block device (`ec2.tf`). While `gp3` is a performant and cost-effective volume type, all I/O operations from the OS, application, and database are funneled through this single volume. The volume is not encrypted, as noted by a `trivy:ignore` for rule `AWS-0131`.

#### Networking
*   **Request Flow**: User traffic is routed through a CloudFront distribution to the EC2 instance's public IP address on port 3000 (`cloudfront.tf`).
*   **Caching**: CloudFront caching is explicitly disabled via the `Managed-CachingDisabled` policy. This means every single request from a client is passed directly to the origin EC2 instance, which must then generate and serve a response. This places the entire serving load on the small `t3.micro` instance.
*   **Security Groups & NACLs**: The EC2 security group correctly allows inbound traffic only from CloudFront's IP ranges on the application port (3000). Network ACLs are in place but are configured to allow all HTTP/HTTPS traffic, which is appropriate for the public subnets.

#### Concurrency & Availability
*   **Single-Instance Architecture**: The entire stack is a single point of failure. A failure of the EC2 instance, the Docker service, or either of the containers will result in a complete outage.
*   **Scheduled Downtime**: The `scheduler.tf` configuration implements a daily stop/start schedule for the EC2 instance to save costs. The service is only available from 5 AM to 7 PM AEST, Monday to Friday. It is unavailable on weekends and outside of these core hours.
*   **No Auto-Scaling**: The system cannot scale horizontally to meet increased demand. Performance will degrade significantly under moderate to high load.

### Identified Bottlenecks & Risks

1.  **Disabled CloudFront Caching**: This is the most significant performance bottleneck. By not caching static assets (CSS, JS, images, fonts) at the edge, every page load puts maximum strain on the origin instance. This leads to slower page load times for users and unnecessarily high CPU/network load on the server.

2.  **Co-located Application and Database**: Running the application and database on the same small host is a critical performance risk. PostgreSQL can be memory and I/O intensive. During periods of high application traffic or database activity (like indexing or complex queries), the two services will starve each other of resources, leading to severe performance degradation or crashes.

3.  **Insufficient Instance Sizing**: A `t3.micro` instance with 1 GiB of RAM is likely insufficient to reliably run both a Node.js application and a PostgreSQL database, especially under real-world load. The burstable CPU model means that sustained traffic will quickly exhaust CPU credits and lead to throttling.

4.  **Single Point of Failure (SPOF)**: The architecture has no redundancy. Any hardware or software failure on the single EC2 instance will lead to data loss (if not yet written to the EBS volume) and a service outage until it is manually restored.

### Recommendations

#### Quick Wins (Low Effort, High Impact)

1.  **Enable Sensible CloudFront Caching**:
    *   **Recommendation**: Replace the `Managed-CachingDisabled` policy with a policy that caches static assets. For a start, AWS's `Managed-CachingOptimized` policy is a good default. This may require ensuring Wiki.js sets appropriate `Cache-Control` headers.
    *   **Rationale**: Offloading requests for static assets to the CloudFront edge network will drastically reduce the load on the EC2 instance and improve page load speeds for users globally.

2.  **Right-Size the EC2 Instance**:
    *   **Recommendation**: Upgrade the instance type from `t3.micro` to at least a `t3.small` (2 GiB RAM) or `t3.medium` (4 GiB RAM).
    *   **Rationale**: The additional memory is crucial for allowing the database and application to run without constant resource contention. Monitor CPU utilization and credit balance to ensure the instance is not being throttled.

#### Longer-Term Improvements (Higher Effort, Architectural Change)

1.  **Use a Managed Database (Amazon RDS)**:
    *   **Recommendation**: Migrate the PostgreSQL database from a Docker container to an Amazon RDS or Aurora Serverless instance.
    *   **Rationale**: Decoupling the database is the most important architectural improvement. It provides dedicated compute/memory/IOPS, automated backups, high availability options, and removes the primary source of resource contention from the application server.

2.  **Move EC2 to Private Subnet with an ALB**:
    *   **Recommendation**: Place an Application Load Balancer (ALB) in the public subnets and move the EC2 instance into a private subnet. The CloudFront distribution would point to the ALB, which then forwards traffic to the instance.
    *   **Rationale**: This enhances security by removing the application server from the public internet. It also provides robust health checking and is a prerequisite for implementing auto-scaling.

3.  **Implement Auto Scaling**:
    *   **Recommendation**: Once the database is external, place the EC2 instance behind an Auto Scaling Group with a scaling policy based on CPU utilization or request count.
    *   **Rationale**: This would allow the application to automatically scale out to handle traffic spikes and scale in to save costs, providing both elasticity and improved availability.

4.  **Encrypt EBS Volume**:
    *   **Recommendation**: Remove the `checkov:skip` and `trivy:ignore` comments for `CKV_AWS_131` and `AWS-0131` and enable EBS encryption.
    *   **Rationale**: The performance impact of EBS encryption on modern Nitro-based instances is negligible. Enabling it is a standard security best practice to protect data at rest.
