# Wiki.js Support Guide

This guide is designed for the support team to understand, troubleshoot, and resolve common issues with the Wiki.js deployment on AWS. It focuses on providing clear explanations and actionable steps, even without deep technical knowledge.

## How the System Works (In Plain Language)

Imagine Wiki.js as a special website that helps teams share information. This website lives on a powerful virtual computer in Amazon's cloud (AWS EC2).

Here's how it generally works:

1.  **You Open Your Browser:** When you type the wiki's address (like `wiki.yourcompany.com`) into your web browser, your request first goes to a global delivery service called **CloudFront**. Think of CloudFront as a smart traffic cop that makes sure your request goes to the right place quickly and securely.
2.  **Security Check:** CloudFront encrypts your connection (HTTPS) to keep your information private and adds extra security rules to protect the website.
3.  **Talking to the Computer:** CloudFront then sends your request to our virtual computer (EC2 instance) in Australia (ap-southeast-2).
4.  **Running the Wiki:** On this virtual computer, two special programs are running inside containers:
    *   One program is the **Wiki.js application** itself, which handles displaying pages and editing content.
    *   The other is a **PostgreSQL database**, which is like a smart filing cabinet that stores all the wiki's pages, user accounts, and other data. All the important wiki data is saved securely to a special hard drive (EBS volume) attached to the virtual computer.
5.  **Getting Your Page:** The Wiki.js application talks to the database to get the content you requested, and then sends it back through CloudFront to your browser.

**Cost Savings:** To save money, the virtual computer can be set to automatically turn off at night and turn back on in the morning. This is handled by a special AWS scheduler.

**How We Fix Things:** If we ever need to look directly at the virtual computer (EC2 instance), we use a secure tool called **SSM Session Manager**, which is like a remote control that doesn't require us to open up any risky connections.

## What Can Go Wrong and Why

Most issues relate to the wiki not being accessible or performing as expected. Here are the main things that can go wrong:

### 1. Website Becomes Unavailable After a Restart

*   **What happens:** The wiki website completely stops working after the virtual computer (EC2 instance) turns off and then turns back on (e.g., overnight). Users see an error page or a message that the site cannot be reached.
*   **Why:** CloudFront needs a specific address (like a public DNS name) to find the virtual computer that hosts the wiki. When the virtual computer stops and starts, AWS often gives it a *new* address. CloudFront isn't automatically updated with this new address, so it keeps trying to send requests to the old, non-existent address.

### 2. Website is Slow or Unresponsive

*   **What happens:** Pages load very slowly, or actions within the wiki take a long time to complete.
*   **Why:**
    *   **Underpowered computer:** The virtual computer (EC2 instance) might not be powerful enough to handle the current amount of users or tasks.
    *   **Database issues:** The database might be overloaded or experiencing problems.
    *   **Network congestion:** While less common for a single instance, network issues could contribute.

### 3. Security Alerts

*   **What happens:** Security scanning tools might flag issues, or an external audit points out potential vulnerabilities.
*   **Why:**
    *   **Unencrypted internal traffic:** Currently, the connection between CloudFront and the virtual computer (EC2) uses unencrypted HTTP. While CloudFront handles the encryption for users, internal traffic is not encrypted, which could be a risk in very specific scenarios.
    *   **Overly broad permissions:** The virtual computer is allowed to send *any* traffic out to the internet, which is not ideal from a security perspective. Similarly, some administrative access permissions are broader than strictly necessary.
    *   **Data not encrypted at rest:** The main hard drive (EBS volume) where wiki data is stored is not encrypted. This is a general security best practice.

## How to Identify and Interpret Errors or Failure States

When a user reports an issue, here’s how to gather initial information:

### Is the Wiki.js Website Loading?

*   **Symptom:** Users report they cannot access `wiki.yourcompany.com` (or the configured domain). They see browser errors like "This site can't be reached," "DNS\_PROBE\_FINISHED\_NXDOMAIN," or "502 Bad Gateway" / "504 Gateway Timeout" from CloudFront.
*   **Interpretation:**
    *   **"Site can't be reached" / DNS errors:** Indicates a problem with the domain name not pointing correctly, or CloudFront itself isn't resolving.
    *   **502 / 504 errors from CloudFront:** This often means CloudFront *can* be reached, but it can't connect to our virtual computer (EC2 instance) or the virtual computer isn't responding in time. This is a strong indicator of the "EC2 Public DNS changed" issue.
    *   **"Connection refused" / "ERR\_CONNECTION\_REFUSED":** The virtual computer might be down or the firewall is blocking CloudFront.

### Is the Virtual Computer (EC2 Instance) Running?

*   **Symptom:** The website is down, and you suspect the EC2 instance might be stopped.
*   **Interpretation:** If the instance is in a "stopped" state when it should be running (during business hours), the scheduler might have failed, or the schedule is incorrect. If it's running but the website is down, the problem is likely with CloudFront's origin or the Docker containers on the EC2.

### Is the Website Slow?

*   **Symptom:** Users complain about long loading times or unresponsiveness.
*   **Interpretation:** This is harder to diagnose without technical tools. It could indicate the EC2 instance is struggling, or the database is under stress.

## What Actions Support Can Take vs. What Requires a Developer

### Support Team Actions (Initial Troubleshooting)

1.  **Check Website Availability:**
    *   Try accessing `wiki.yourcompany.com` from your own browser.
    *   Use an online tool like `downforeveryoneorjustme.com` to see if the site is down for everyone or just the reporting user.
2.  **Verify EC2 Instance Status (Requires AWS Console Access - Read-Only):**
    *   Log into the AWS Console.
    *   Navigate to **EC2 > Instances**.
    *   Find the instance named `*-wiki-ec2` (the exact name will vary but will contain `wiki-ec2`).
    *   Check its "Instance State" column. Is it `running` or `stopped`?
    *   If it's `stopped` during working hours, and the website is down, inform a developer immediately.
3.  **Check CloudFront Distribution Status (Requires AWS Console Access - Read-Only):**
    *   Log into the AWS Console.
    *   Navigate to **CloudFront > Distributions**.
    *   Find the distribution associated with `wiki.yourcompany.com`.
    *   Check its "Last modified" time. If it was modified recently and the site is down, this could be a factor.
    *   Under the "Origins" tab, note the "Origin Domain Name". If the EC2 instance has restarted, this domain name will likely be stale.
4.  **Confirm DNS Records (Requires DNS Management Access - Read-Only):**
    *   Check the CNAME record for `wiki.yourcompany.com` in Route53 or your domain provider. It should point to the CloudFront distribution's domain name (e.g., `dxxxxxxxxxxxxxx.cloudfront.net`). If this is incorrect, the site won't load.

### Developer Required Actions

Any issue requiring changes to the AWS infrastructure (Terraform code) or deep inspection of the EC2 instance's internal state (Docker logs, system logs) requires a developer.

*   **Website Unavailable (after EC2 restart):** A developer must update the Terraform code to use a static IP address (Elastic IP) or an Application Load Balancer (ALB) as the CloudFront origin. This is a critical fix.
*   **Security Concerns:** Any remediation for unencrypted traffic, overly broad permissions, or unencrypted EBS volumes requires a developer to modify and re-deploy the Terraform configuration.
*   **Performance Issues (Slowness):** A developer would need to investigate resource utilization on the EC2 instance, check database performance, and potentially scale up the EC2 instance type.
*   **Docker Container Issues:** If the EC2 instance is running but the Wiki.js application or database isn't starting correctly inside Docker, a developer will need to use SSM Session Manager to troubleshoot on the instance itself.

## Key Log and Monitoring Locations

For detailed investigation, a developer will typically check these areas:

*   **AWS CloudWatch Logs (for EC2):** System logs, application logs from Docker containers (if configured).
*   **AWS CloudFront Access Logs:** If enabled, these logs show every request made to CloudFront and how it was handled, including error codes.
*   **AWS Console (EC2 Instance Monitoring Tab):** Provides CPU utilization, network I/O, and disk usage metrics for the virtual computer.
*   **SSM Session Manager:** Allows a developer to get a secure shell directly into the EC2 instance to check Docker logs (`docker logs <container_name>`), system processes, and other application-specific logs.

## Frequently Asked Questions (FAQ)

### Q1: The wiki page says "This site can't be reached" or "502 Bad Gateway". What do I do?

*   **A:** First, try reloading the page. If that doesn't work, this usually means the virtual computer hosting the wiki has restarted, and CloudFront can no longer find it. Please report this to a developer immediately.

### Q2: Is my data safe on the wiki?

*   **A:** Yes, all traffic to and from your browser is encrypted (HTTPS). The data in the database is stored on a dedicated hard drive for the virtual computer. While there are some areas identified for security improvements (like encrypting the hard drive and restricting internal network traffic more), these are being addressed by developers to ensure a high level of security.

### Q3: Why does the wiki sometimes go offline overnight?

*   **A:** To save costs, the virtual computer (EC2 instance) hosting the wiki is often configured to automatically shut down after business hours and restart before the next workday. If you find it's offline during working hours, please report it, as there might be an issue with the automated schedule.

### Q4: I'm seeing an outdated page, even after someone updated it.

*   **A:** CloudFront sometimes caches (remembers) old versions of pages. While caching is mostly disabled for this wiki, you can try a "hard refresh" in your browser (Ctrl+F5 on Windows/Linux, Cmd+Shift+R on Mac) to force it to load the latest version. If the problem persists, it might indicate a more complex caching issue that a developer needs to investigate.
