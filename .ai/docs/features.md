# Wiki.js on AWS: Your Collaborative Content Platform

This document describes the key features and operational aspects of the Wiki.js deployment on Amazon Web Services (AWS), tailored for a Product and Marketing audience.

## What is this product?

This solution provides a fully managed and secure Wiki.js instance, hosted on AWS. It serves as a central, easy-to-use platform for teams to collaborate, share knowledge, and publish documentation within a controlled environment. The entire setup is automated and designed for efficiency, reliability, and cost-effectiveness.

## Key Features and Capabilities

### Content Hosting & Delivery
*   **Modern Wiki Platform:** Powered by Wiki.js, a feature-rich and user-friendly content management system for wikis.
*   **Robust Data Storage:** Utilizes a PostgreSQL database for reliable and scalable storage of all wiki content and user data.
*   **Dedicated Server:** Runs on a dedicated AWS virtual server (EC2) that hosts both the Wiki.js application and its database, managed efficiently through Docker containers.
*   **Global Content Delivery:** Content is delivered quickly and securely to users worldwide via AWS CloudFront, a global content delivery network.

### Security & Access Control
*   **Encrypted Connections:** All interactions with the wiki are secured using HTTPS, ensuring that data in transit is encrypted with industry-standard TLS certificates managed by AWS Certificate Manager (ACM).
*   **Advanced Security Headers:** CloudFront automatically enforces security best practices by applying various HTTP security headers (e.g., HSTS, X-Frame-Options), protecting against common web-based attacks.
*   **Secure Server Administration:** Access to the underlying server is restricted to authorized administrators via AWS Systems Manager (SSM) Session Manager. This eliminates the need for traditional SSH keys, enhancing security.
*   **Network Firewall:** A dedicated network firewall (Security Group) ensures that only legitimate web traffic originating from CloudFront can reach the wiki application server.
*   **Automated Security Scans:** The infrastructure configuration undergoes continuous automated security scanning (using Trivy and Checkov) to identify and mitigate potential vulnerabilities, ensuring a high level of security.

### Cost Optimization
*   **Automated Scheduling:** To help manage operational costs, the wiki server can be configured to automatically stop and start based on a predefined schedule (e.g., stopping after business hours and restarting before the next workday).

## Integration Points

The Wiki.js solution seamlessly integrates with core AWS services and other essential technologies:

*   **AWS CloudFront:** Distributes content globally and manages secure web traffic.
*   **AWS Certificate Manager (ACM):** Provides and manages the SSL/TLS certificates required for HTTPS.
*   **AWS EC2:** Supplies the virtual server infrastructure for hosting the wiki.
*   **AWS Systems Manager (SSM):** Facilitates secure administrative access and automation.
*   **AWS EventBridge Scheduler:** Automates the EC2 server's stop/start schedule for cost savings.
*   **AWS Route53:** Used for DNS validation of SSL certificates and to point your custom domain to the Wiki.js instance.
*   **Docker Compose:** Orchestrates the Wiki.js application and PostgreSQL database containers on the EC2 server.

## Configuration Options for Your Wiki

You can customize your Wiki.js deployment using the following easy-to-set options:

*   **Custom Web Address:** Define the domain name (e.g., `wiki.yourcompany.com`) for accessing your wiki.
*   **Server Performance:** Select the type of server instance (e.g., `t3.micro` for smaller wikis) to match your performance and budget needs.
*   **Cost-Saving Schedule:** Enable or disable the automatic stop/start schedule for the server to optimize operational expenses.
*   **Environment Tag:** Assign a descriptive name (e.g., `production`, `development`) to easily identify and manage your AWS resources.
*   **Network Range (Advanced):** Configure the network address range for the private network that hosts your wiki.

## Operational Behaviors

*   **Automatic Secure Redirection:** Any attempt to access your wiki using an insecure HTTP connection will automatically be redirected to a secure HTTPS connection.
*   **Scheduled Availability:** When enabled, the wiki server will automatically power down during specified off-hours and power back on at the start of the next working period, balancing availability with cost savings.
*   **Domain Verification:** To enable secure web access, a simple DNS record must be created in your domain's settings to validate the SSL certificate. The required records will be provided upon deployment.
*   **Custom Domain Linkage:** After the wiki is deployed, a CNAME record will need to be configured with your DNS provider to connect your chosen domain name to the CloudFront distribution. The CloudFront domain name will be provided as an output.
*   **Secure Server Access:** Administrative access to the underlying EC2 instance is provided via AWS Systems Manager Session Manager, and the instance ID is provided as an output.

## Architecture Overview

Here's a simplified view of how the Wiki.js solution operates:

+---------------+        +-------------------+        +---------------------------+
|   Your Web    |        |                   |        |                           |
|   Browser     |------->| AWS CloudFront    |------->| AWS EC2 Instance          |
|               |        | (Global Content   |        | (Runs Wiki.js + PostgreSQL|
+---------------+        |  Delivery Network)|        |  via Docker Compose)      |
                         +-------------------+        |                           |
                                 |  ^                 +-------------+-------------+
                                 |  |                               |
                                 |  +-------------------------------+
                                 |    Secure Access via AWS SSM Session Manager
                                 |
                                 +---------------------------------+
                                       Managed TLS Certificate
                                       (from AWS Certificate Manager)
