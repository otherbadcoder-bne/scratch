# Wiki.js Deployment Architecture Overview

This document provides a technical overview of the Wiki.js deployment within the `scratch` repository. It covers the system's architecture, data flow, the role of AWS services, key design decisions, and the deployment model.

## System Overview

This project deploys a standalone Wiki.js instance on AWS using Terraform. It is designed as an independent module within a personal workspace for infrastructure-as-code experiments. The architecture prioritizes simplicity, security, cost-efficiency, and automation for a single Wiki.js instance.

The application, along with its PostgreSQL database, runs within Docker containers on a single EC2 instance. Public access is facilitated by an AWS CloudFront distribution, which handles TLS termination and applies security headers. Management access to the EC2 instance is exclusively via SSM Session Manager.

## Component Diagram

```
+------------------+     HTTPS/443     +-----------------------+     HTTP/3000     +----------------------+
|   Internet User  |------------------>| AWS CloudFront        |------------------->| AWS EC2 Instance     |
|     (Browser)    |                   | (Global CDN, TLS Term)|                    | (Amazon Linux 2023)  |
+------------------+                   +-----------+-----------+                    |                      |
                                                   |                                | +------------------+ |
                                                   |                                | | Docker Compose   | |
                                                   |                                | | - Wiki.js        | |
                                                   |                                | | - PostgreSQL     | |
                                                   |                                | +------------------+ |
                                                   |                                |                      |
                                                   |                                +----------+-----------+
                                                   |                                           |
                                                   |          (SSM Session)                    |
                                                   +<------------------------------------------+
                                                   |        AWS Systems Manager                |
                                                   |          (Session Manager)                |
                                                   |                                           |
                                                   +------------------------------------------->
                                                           AWS EventBridge Scheduler
                                                           (EC2 Stop/Start Cron)
```

## Data Flow End-to-End

1.  **User Request**: A user accesses the Wiki.js instance via a specified domain name (e.g., `wiki.example.com`). The request is sent over HTTPS (port 443) to the AWS CloudFront distribution.
2.  **CloudFront Processing**: CloudFront terminates the TLS connection using an ACM certificate provisioned in `us-east-1`. It then forwards the request to the EC2 instance origin over unencrypted HTTP on port 3000. Caching is disabled, but security headers are injected into the response.
3.  **EC2 Security Group**: The EC2 instance's security group allows inbound TCP traffic on port 3000 only from the CloudFront managed prefix list.
4.  **Docker & Application**: On the EC2 instance, Docker Compose orchestrates the `ghcr.io/requarks/wiki:2` container, which receives the request.
5.  **Database Interaction**: The Wiki.js application communicates with the `postgres:15-alpine` container over the internal Docker network to perform database operations. PostgreSQL data is persisted on an EBS volume mounted via a Docker volume (`db-data`).
6.  **Response**: The processed response travels back through CloudFront to the user's browser.

Administrative access to the EC2 instance is conducted via AWS Systems Manager (SSM) Session Manager, providing secure shell access without direct SSH. An EventBridge Scheduler is configured to stop and start the EC2 instance during specified hours for cost optimization.

## AWS Services and Their Roles

*   **EC2 (Elastic Compute Cloud)**: Hosts the Wiki.js and PostgreSQL Docker containers on a single `t3.micro` Amazon Linux 2023 instance.
*   **VPC (Virtual Private Cloud)**: Provides network isolation (`10.0.0.0/16`) with 3 public and 3 private subnets across three availability zones.
*   **CloudFront**: Acts as the public entry point, handling TLS termination, redirecting HTTP to HTTPS, and enforcing security headers.
*   **ACM (AWS Certificate Manager)**: Provisions and manages the public SSL/TLS certificate for CloudFront, specifically in `us-east-1`.
*   **IAM (Identity and Access Management)**:
    *   **EC2 Instance Role**: Grants permissions (`AmazonSSMManagedInstanceCore`) for the instance to communicate with SSM.
    *   **Scheduler Role**: Provides permissions for EventBridge to start and stop the EC2 instance via SSM Automation documents.
*   **SSM (Systems Manager)**:
    *   **Session Manager**: Facilitates secure, shell-based access to the EC2 instance without SSH keys.
    *   **Parameter Store**: Used to dynamically retrieve the latest Amazon Linux 2023 AMI ID.
*   **EventBridge Scheduler**: Automates the stopping and starting of the EC2 instance based on a cron schedule for cost savings.
*   **Security Groups**: Stateful firewalls for the EC2 instance, restricting ingress to CloudFront on port 3000 and allowing unrestricted egress.
*   **Network ACLs**: Stateless firewalls for public and private subnets, providing an additional layer of network defense.
*   **Internet Gateway**: Enables internet connectivity for resources in public subnets.

## Infrastructure Design Decisions

*   **Infrastructure as Code (Terraform)**: The entire AWS infrastructure is defined and managed using Terraform, ensuring reproducibility and version control.
*   **Docker Compose**: Used to orchestrate the Wiki.js application and its PostgreSQL database on a single EC2 instance for simplified deployment and management.
*   **CloudFront for Public Access**: Leverages CloudFront for global content delivery, TLS termination, and security header enforcement.
*   **SSM Session Manager for Administration**: Prioritizes security by disallowing SSH access and enforcing SSM Session Manager for server administration.
*   **Automated Cost Optimization**: Implements an EventBridge Scheduler to automatically stop and start the EC2 instance outside of business hours.
*   **Defense-in-Depth**: Utilizes multiple layers of security controls, including Security Groups and Network ACLs.
*   **Explicit AWS Region for ACM**: ACM certificates for CloudFront are explicitly provisioned in `us-east-1` as required by AWS.
*   **Dynamic AMI Selection**: Uses SSM Parameter Store to always retrieve the latest Amazon Linux 2023 AMI, ensuring instances are launched with up-to-date images.
*   **Security Scanning Integration**: Pre-commit hooks and GitHub Actions integrate Trivy and Checkov for automated security and policy-as-code scanning.

## Deployment Model

The deployment follows an Infrastructure as Code (IaC) model using Terraform.

1.  **Terraform Configuration**: The infrastructure is defined across multiple `.tf` files within the `wiki.js/` directory (e.g., `main.tf`, `vpc.tf`, `ec2.tf`, `cloudfront.tf`).
2.  **User Data Script**: The EC2 instance is configured at launch via a `user-data.sh.tftpl` script. This script installs Docker and Docker Compose, then uses the embedded `docker-compose.yml` content to deploy the Wiki.js and PostgreSQL containers.
3.  **GitHub Actions CI**: The `terraform-ci.yml` workflow automates formatting, validation, linting, security checks, and Terraform plan generation on Pull Requests to `main`.
4.  **Pre-Commit Hooks**: Local `pre-commit` hooks enforce code quality, security scanning (Trivy, Gitleaks, Checkov), Terraform standards (fmt, validate, tflint, terraform-docs), and Infracost analysis before commits and pushes.

## Environment Differences

The Terraform configuration includes an `environment` variable, which defaults to `"shared-services"`. This variable is primarily used for tagging AWS resources, allowing for logical grouping and identification across different deployment contexts (e.g., `production`, `development`). While explicit environment-specific configurations are not deeply nested, the tagging provides a mechanism to differentiate resources. The `schedule_enabled` variable also allows for environment-specific control over cost-saving schedules.

## Notable Design Patterns

*   **Infrastructure as Code**: Full infrastructure defined in Terraform.
*   **Immutable Infrastructure (Partial)**: EC2 instances are configured via user data scripts at launch, promoting consistency. However, the use of scheduled stop/start and an Elastic IP (as a potential fix for origin issues) indicates some statefulness is tolerated for cost.
*   **Twelve-Factor App Principles (Partial)**: Configuration (database credentials, domain name) is managed via environment variables (in Docker Compose) and Terraform variables, separating config from code.
*   **Defense-in-Depth**: Multiple security layers including VPC, Subnets, Network ACLs, Security Groups, IAM roles, and CloudFront security headers.
*   **Cost Optimization**: Automated scheduling of EC2 instance to reduce operational costs.
*   **Single-Instance Application**: A simple deployment model with Wiki.js and PostgreSQL co-located on a single EC2 instance via Docker Compose.
