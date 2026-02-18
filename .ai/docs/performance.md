# Wiki.js Deployment Performance Analysis

This document provides an analysis of the Wiki.js deployment's performance characteristics, identifies potential bottlenecks, and offers recommendations for improvement, suitable for a technical audience.

## Current Performance Profile

The current Wiki.js deployment utilizes a minimalist architecture, optimized for cost-efficiency and ease of deployment within a sandbox environment.

### Infrastructure Sizing and Resource Allocation
*   **EC2 Instance**: The Wiki.js application and its PostgreSQL database run on a single `t3.micro` EC2 instance. This instance type is part of the burstable performance family, suitable for workloads with moderate baseline CPU utilization and occasional spikes.
*   **EBS Storage**: The EC2 instance's root volume is a 20GB `gp3` EBS volume. `gp3` volumes offer a consistent baseline performance with configurable IOPS and throughput, providing adequate storage and I/O for a small application.
*   **Database**: PostgreSQL 15-alpine runs as a Docker container, storing its data persistently on the host's EBS volume.
*   **Networking**: The application is deployed within a VPC with both public and private subnets across three Availability Zones, though only one public subnet is currently utilized for the EC2 instance.

### Content Delivery and Caching
*   **CloudFront Distribution**: A CloudFront distribution fronts the EC2 instance, providing TLS termination and applying security headers.
*   **Caching Strategy**: The CloudFront configuration explicitly uses the `Managed-CachingDisabled` policy. This means that all requests hitting the CloudFront distribution are forwarded directly to the EC2 origin, with no content being cached at the edge locations.

### Operational Availability
*   **Scheduled Stops/Starts**: The EC2 instance is configured with an EventBridge Scheduler to automatically stop outside working hours (Mon-Fri, 7 PM - 7 AM AEST) and start before the next workday. This strategy aims to reduce operational costs.

## Identified Bottlenecks and Risks

Several aspects of the current architecture present potential performance bottlenecks or risks to availability, particularly if the Wiki.js instance were to experience increased traffic or be considered for production use.

*   **No CloudFront Caching**: The disabled caching policy is the most significant performance bottleneck. Every single request, regardless of content type (static assets like images, CSS, JavaScript, or dynamic page requests), traverses from CloudFront's edge location to the EC2 instance. This significantly increases latency for users and places a higher load directly on the `t3.micro` EC2 instance.
*   **Single Point of Failure**: The entire application (Wiki.js and its database) resides on a single EC2 instance. Any failure of this instance, its underlying host, or the Docker containers within it will result in complete service unavailability.
*   **Dynamic EC2 Origin for CloudFront**: As identified in `.ai/docs/bug-list.md`, the CloudFront distribution uses the EC2 instance's public DNS name as its origin. When an EC2 instance is stopped and started, its public DNS name changes. This renders the CloudFront distribution's origin invalid, leading to service disruption until the CloudFront distribution is manually updated or the DNS record is propagated. This is a critical availability and performance risk.
*   **`t3.micro` Instance Resource Limits**: While cost-effective, a `t3.micro` instance has limited CPU credits and memory. Under sustained or bursty traffic, the CPU credits can be exhausted, leading to CPU throttling and degraded application performance.
*   **Cold Starts after Scheduled Downtime**: The scheduled stopping and starting of the EC2 instance introduce "cold start" periods. During these times, the instance needs to boot up, Docker containers need to initialize, and the Wiki.js application needs to fully start, resulting in temporary unavailability and reduced performance until all services are operational.
*   **Shared Resources on Single Host**: Running both the Wiki.js application and its PostgreSQL database on the same EC2 instance means they contend for the same CPU, memory, and I/O resources. This can limit the performance of both components under load.

## Specific Recommendations with Rationale

### Quick Wins (Immediate Impact, Lower Effort)

1.  **Implement a Static CloudFront Origin**:
    *   **Rationale**: The current reliance on the EC2 instance's dynamic public DNS name causes service outages when the instance restarts. Using a static endpoint ensures continuous availability of the CloudFront distribution.
    *   **Recommendation**: Attach an **Elastic IP address** to the EC2 instance. Update the CloudFront origin's `domain_name` to use this static Elastic IP.

2.  **Enable Selective CloudFront Caching**:
    *   **Rationale**: Disabling caching for all content drastically increases latency and origin load. Caching static assets like CSS, JavaScript files, and images significantly reduces the burden on the EC2 instance and improves load times for users.
    *   **Recommendation**: Create a more granular CloudFront cache policy. For instance, cache static content (e.g., `/assets/*`, `/uploads/*`) for an appropriate duration while maintaining `CachingDisabled` or minimal caching for dynamic HTML content.

3.  **Monitor `t3.micro` Performance**:
    *   **Rationale**: The `t3.micro` instance is susceptible to CPU credit exhaustion under sustained load. Proactive monitoring can identify if it's becoming a bottleneck before it impacts users.
    *   **Recommendation**: Implement AWS CloudWatch monitoring for the EC2 instance, focusing on CPU Utilization and `CPUCreditBalance` metrics. If credit balance frequently drops or CPU utilization consistently hits limits, an instance type upgrade may be necessary.

### Longer-Term Improvements (Higher Impact, Moderate to High Effort)

1.  **Introduce an Application Load Balancer (ALB)**:
    *   **Rationale**: An ALB provides a stable, highly available endpoint for the application, regardless of EC2 instance restarts or failures. It also enables moving the EC2 instance to a private subnet for enhanced security.
    *   **Recommendation**:
        *   Place the EC2 instance in a private subnet.
        *   Deploy an ALB in the public subnets, configured to forward traffic to the EC2 instance (possibly via a Target Group).
        *   Update the CloudFront origin to point to the ALB's DNS name. This also inherently solves the dynamic EC2 public DNS issue.

2.  **Enable HTTPS Between CloudFront and Origin**:
    *   **Rationale**: Sending traffic unencrypted (`http-only`) between CloudFront and the EC2 origin is a security risk. While not a direct performance issue, it's a critical security vulnerability that should be addressed in a production-grade system.
    *   **Recommendation**: Configure the Wiki.js Docker setup (or introduce a proxy like Nginx on the EC2 instance) to handle HTTPS traffic on an internal port. Update the CloudFront `custom_origin_config` to use `https-only` and the appropriate HTTPS port.

3.  **Migrate Database to AWS RDS**:
    *   **Rationale**: Running the database on the same EC2 instance creates a single point of failure and resource contention. AWS RDS provides a managed, scalable, and highly available database service, offloading operational overhead.
    *   **Recommendation**: Provision an AWS RDS PostgreSQL instance. Update the Wiki.js Docker Compose configuration to connect to the RDS endpoint instead of the local `database` service. This would require moving the EC2 instance to a private subnet with appropriate database connectivity.

4.  **Implement Auto Scaling Group for EC2**:
    *   **Rationale**: For increased availability and scalability, an Auto Scaling Group (ASG) can automatically launch new EC2 instances to replace unhealthy ones or to scale out during periods of high demand.
    *   **Recommendation**: Create an Auto Scaling Group with a Launch Template that provisions the Wiki.js EC2 instance. Place the ASG behind an ALB. This would require further re-architecting of the Docker Compose setup to be stateless and suitable for multi-instance deployment.

## Infrastructure Sizing Observations

*   **`t3.micro` Instance**: As a "scratch/sandbox" environment, the `t3.micro` instance is a cost-effective choice. However, for any workload beyond very light personal use, it is critically undersized and will likely experience performance degradation and service interruptions due to CPU credit exhaustion.
*   **20GB `gp3` EBS Volume**: The 20GB size is adequate for a basic operating system and initial application data. The `gp3` type offers decent baseline I/O performance. For a growing wiki with more content, persistent file uploads, or increased database activity, a larger volume with higher provisioned IOPS/throughput might be required.
*   **VPC Structure**: The initial VPC setup with public and private subnets across multiple Availability Zones provides a robust foundation for future scalability and high availability enhancements, even if not fully utilized by the current single-instance deployment.
