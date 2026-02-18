# Wiki.js Deployment Architecture

## System Overview

This document outlines the architecture for the Wiki.js deployment, an independent project managed within the `scratch` repository. The system provides a single Wiki.js instance running on AWS, provisioned and managed entirely through Terraform. The design prioritizes security, cost-efficiency, and automation.

The application itself, along with its PostgreSQL database, runs within Docker containers on a single EC2 instance. Public access is fronted by a CloudFront distribution, which provides TLS termination and applies security headers.

## Component Diagram

```mermaid
graph TD
    subgraph "Internet User"
        User[Browser]
    end

    subgraph "AWS Cloud"
        subgraph "Global Services"
            CF[CloudFront Distribution<br/>Aliases: var.domain_name]
            ACM[ACM Certificate<br/>Region: us-east-1]
        end

        subgraph "VPC (ap-southeast-2)"
            subgraph "Public Subnet"
                EC2[EC2 Instance<br/>Type: var.instance_type]
                EC2 -- Docker --> WikiContainer[Wiki.js Container]
                EC2 -- Docker --> DBContainer[PostgreSQL Container]
                DBContainer -- Mounts --> EBS[EBS Volume (db-data)]
            end
        end

        subgraph "Management & Automation"
            Scheduler[EventBridge Scheduler<br/>CRON: Stop/Start EC2]
            SSM[Systems Manager<br/>Session Manager for Shell Access]
        end
    end

    User -- HTTPS/443 --> CF
    CF -- Uses --> ACM
    CF -- HTTP/3000<br/>(Origin Request) --> EC2

    EC2 -- Manages --> WikiContainer
    EC2 -- Manages --> DBContainer
    Scheduler -- "ssm:Start/StopInstances" --> EC2
    Admin[Admin User] -- "aws ssm start-session" --> SSM -- Session --> EC2
```

## Data Flow

1.  **User Request**: A user accesses the wiki by navigating to `var.domain_name` in their browser. The request is sent over HTTPS (port 443) to AWS CloudFront.
2.  **CloudFront**: The CloudFront distribution terminates the TLS connection using an ACM certificate. It forwards the request to the origin—the EC2 instance—over HTTP on port 3000. Caching is disabled, but security headers (HSTS, XSS protection, etc.) are injected into the response.
3.  **EC2 & Security Group**: The request from the CloudFront managed prefix list is allowed by the EC2 instance's security group on TCP port 3000.
4.  **Docker & Application**: The EC2 instance, running Amazon Linux 2023, is configured via user data to run Docker Compose. The request is received by the `ghcr.io/requarks/wiki:2` container.
5.  **Database**: The Wiki.js application communicates with the `postgres:15-alpine` container over the internal Docker network to query or persist data. The PostgreSQL data is persisted on the host's EBS volume via a Docker volume mount (`db-data`).
6.  **Response**: The response travels back through the same path to the user.

Administrative access to the EC2 instance is handled exclusively via SSM Session Manager, avoiding the need for SSH keys or open SSH ports.

## AWS Services and Their Roles

### Compute & Application Hosting
*   **EC2**: A single instance (`t3.micro` by default) runs the Docker engine. The instance is launched in a public subnet and its AMI is dynamically sourced from the latest Amazon Linux 2023 SSM parameter.
*   **Docker Compose**: Although not an AWS service, it is core to the application deployment, orchestrating the Wiki.js and PostgreSQL containers on the EC2 host.

### Networking & Content Delivery
*   **VPC**: A dedicated VPC (`10.0.0.0/16` by default) provides network isolation. It contains 3 public and 3 private subnets across three availability zones.
*   **Internet Gateway**: Provides internet access for the public subnets.
*   **Security Groups**: A security group (`*-wiki-sg`) acts as a stateful firewall for the EC2 instance, allowing ingress traffic only from the CloudFront origin-facing prefix list on port 3000.
*   **Network ACLs**: Stateless firewalls are configured for public and private subnets, providing an additional layer of defense.
*   **CloudFront**: Serves as the public entry point, providing TLS termination, redirecting HTTP to HTTPS, and enforcing security headers on responses.

### Security & Identity
*   **IAM**:
    *   An **EC2 Instance Role** (`*-wiki-ec2`) is attached to the instance, granting it permissions to connect with the SSM service (`AmazonSSMManagedInstanceCore` policy).
    *   A **Scheduler Role** (`*-wiki-scheduler`) is used by EventBridge to gain permissions to start and stop the EC2 instance via SSM Automation documents.
*   **ACM (AWS Certificate Manager)**: Provisions and manages the public SSL/TLS certificate used by CloudFront. The certificate is created in `us-east-1` as required by the service.
*   **SSM (Systems Manager)**:
    *   **Session Manager**: Provides secure, shell-based access to the EC2 instance without requiring SSH.
    *   **Parameter Store**: Used to fetch the latest Amazon Linux 2023 AMI ID, ensuring the instance is always launched with an up-to-date image.

### Automation & Cost Management
*   **EventBridge Scheduler**: Implements a cost-saving schedule (`schedule_enabled = true` by default). It stops the EC2 instance on weekday evenings (7 PM AEST) and starts it on weekday mornings (5 AM AEST) using SSM Automation runbooks (`AWS-StopEC2Instances` and `AWS-StartEC2Instances`).

## Infrastructure Design Decisions

*   **Infrastructure as Code**: The entire infrastructure is defined declaratively using Terraform, enabling automated, repeatable, and version-controlled deployments.
*   **Containerization**: Docker Compose is used to bundle the application and its database dependencies. This simplifies setup on the host, standardizes the application runtime, and makes local development consistent with the deployed environment.
*   **Security-in-Depth**:
    *   **TLS Offloading**: CloudFront, rather than the application server, handles TLS, centralizing certificate management and reducing computational load on the EC2 instance.
    *   **No SSH Access**: Access is restricted to SSM Session Manager, which is authenticated via IAM. This eliminates the risks associated with SSH keys and open ports.
    *   **Least Privilege Networking**: The EC2 security group only allows traffic from CloudFront's known IP ranges on the specific application port. The default VPC security group and NACL are configured to deny all traffic.
    *   **Security Headers**: A CloudFront Response Headers Policy is used to enforce best-practice headers like HSTS, preventing certain client-side attacks.
*   **Cost Optimization**: The EC2 instance is automatically stopped outside of typical business hours via an EventBridge schedule, significantly reducing compute costs for non-critical environments.
*   **Parameterization**: Key configuration values like `domain_name`, `instance_type`, and `environment` are exposed as Terraform variables, allowing the module to be reused for different deployments.
*   **Documented Security Exceptions**: Where security scanner recommendations (Trivy, Checkov) are not implemented, they are explicitly ignored in the code with documented justifications (e.g., cost vs. benefit for WAF, EBS encryption).

## Deployment Model

The infrastructure is deployed using Terraform. The repository is configured with a CI/CD pipeline using GitHub Actions (`terraform-ci.yml`) that triggers on pull requests to the `main` branch. The pipeline validates, lints, and runs a `terraform plan`, posting the output to the pull request for review before any changes are merged and applied.

## Environment Differences

The Terraform configuration is designed to be environment-agnostic through the use of an `environment` variable (defaulting to `shared-services`). This variable is used to prefix or tag all resources, allowing multiple, isolated instances of the infrastructure to be deployed from the same codebase (e.g., for development, staging, or production). However, the provided source files describe a single, unified deployment configuration.
