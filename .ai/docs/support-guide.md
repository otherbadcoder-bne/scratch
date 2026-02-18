This guide is for the support team. It explains how the Wiki.js service works, what can go wrong, and what to do about it.

## How The System Works: A Plain-Language Guide

Imagine the Wiki.js service is like a restaurant.

*   **The Customer (Web Browser):** This is you or a user trying to access the wiki website.
*   **The Bouncer (Amazon CloudFront):** When you go to the wiki's web address, you first meet the bouncer. This service provides a secure, encrypted connection (HTTPS) and checks your request. It's the front door to the service and makes sure traffic flows smoothly and securely. It also has a list of security rules to protect the site.
*   **The Kitchen (EC2 Server):** After the bouncer lets you in, your request goes to the kitchen. This is a small virtual computer (an EC2 instance) running in an Amazon Web Services data center. This computer's only job is to run the wiki software.
*   **The Appliances (Docker):** Inside the kitchen, there are two main appliances running side-by-side. These are managed by a system called Docker Compose.
    1.  **The Chef (Wiki.js software):** This appliance actually prepares the webpage you asked for.
    2.  **The Pantry (PostgreSQL Database):** This appliance stores all the wiki content—the pages, user accounts, and settings. The Chef gets all its ingredients from here.
*   **The Secret Passage (SSM Session Manager):** There is no public SSH access to the server. For security, developers don't log into the server from the open internet. Instead, they use a secure, private tunnel called SSM Session Manager to perform maintenance. This is like the restaurant manager using a special key to a private back door.

In short: A user's request goes through the secure CloudFront bouncer to the EC2 kitchen, where the Wiki.js chef and PostgreSQL pantry work together in their Docker appliance to build the webpage and send it back.

## What Can Go Wrong and Why?

Like any system, things can sometimes break. Here are the most common failure points.

### The Bouncer (CloudFront) Has a Problem
*   **What it looks like:** You might see an error page from "CloudFront" before you even get to the wiki. Common errors are "502 Bad Gateway" or "504 Gateway Timeout".
*   **Why it happens:**
    *   **502 Bad Gateway:** The bouncer can't talk to the kitchen. This usually means the EC2 server is offline, or the Wiki.js application on it has crashed.
    *   **504 Gateway Timeout:** The bouncer knocked on the kitchen door, but the chef took too long to answer. This means the server is probably overwhelmed, very busy, or stuck on a task.

### The Kitchen (EC2 Server) is Down
*   **What it looks like:** The site won't load, and you'll likely see a CloudFront error page (502 or 504).
*   **Why it happens:** The virtual computer itself could have an issue with its hardware (rare), or it might have failed to start up correctly after a maintenance window.

### The Appliances (Docker Containers) Aren't Working
*   **What it looks like:** The site gives a "502 Bad Gateway" error from CloudFront.
*   **Why it happens:** The `docker-compose` system that runs the Wiki.js and PostgreSQL containers might have failed. One of the two containers (the chef or the pantry) could have crashed. The Wiki.js application can't work without its database.

### The Website Certificate Has Expired
*   **What it looks like:** Your web browser (Chrome, Firefox, Safari) shows a big, scary security warning like "Your connection is not private" or "NET::ERR_CERT_DATE_INVALID".
*   **Why it happens:** The security certificate (from ACM) that proves the site is legitimate has expired. These are usually renewed automatically, but sometimes that process can fail.

## How to Identify and Handle Errors

| What You See | What It Means | What Support Can Do | What Needs a Developer |
| :--- | :--- | :--- | :--- |
| A CloudFront "502 Bad Gateway" error | The EC2 server or the Wiki.js application on it is offline or has crashed. | 1. Note the time of the error. 2. Escalate to the development team immediately. This is a critical outage. | Developer needs to use SSM Session Manager to connect to the server, check the status of the `docker` containers, and restart the service or server. |
| A CloudFront "504 Gateway Timeout" error | The server is online but is too slow or overloaded to respond in time. | 1. Note the time of the error. 2. Escalate to the development team. This indicates a performance problem. | Developer needs to investigate server performance (CPU, memory) and check application logs for slow processes. |
| Browser security warning ("Connection not private") | The website's TLS/SSL certificate has expired. | 1. Take a screenshot of the error. 2. **Do not** tell users to click past the warning. 3. Escalate to the development team immediately. | Developer needs to investigate why the ACM certificate's automatic renewal failed and fix it. This is an urgent issue. |
| A Wiki.js-branded error page | The underlying server is fine, but the wiki application itself has encountered an internal error. | 1. Take a screenshot. 2. Try to get the steps the user took to trigger the error. 3. Escalate to the development team. | Developer needs to check the Wiki.js application logs on the server to diagnose the software bug. |
| The site is just very slow | The server is likely experiencing high load. | 1. Ask if it's slow for everyone or just one user. 2. Note the time and escalate to the development team. | Developer needs to analyze server performance and may need to resize the server to a more powerful type. |

## Key Log and Monitoring Locations

The support team does not have direct access to logs. This information is for your awareness of where developers will look when you escalate an issue.

*   **Amazon CloudWatch:** This is the primary monitoring service in AWS. Developers will look here for:
    *   **EC2 Instance Metrics:** CPU Utilization, Memory, Disk Space. A spike in CPU or running out of disk space are common causes of failure.
    *   **Application Logs:** The `user-data.sh.tftpl` script configures the system, but it does not set up a specific agent to forward Docker logs to CloudWatch. A developer will need to connect to the instance via SSM to view logs directly from the Docker containers.
*   **AWS Health Dashboard:** This dashboard reports on the overall health of AWS services. If the whole region is having a problem, it will be posted here.

## FAQ

### The wiki is down, what should I do?
If you see a CloudFront error (502/504), a browser security warning, or the site just won't load, the issue requires a developer to fix. Please follow the escalation steps in the table above and report it immediately.

### A user says the wiki is slow. What can I do?
First, try to confirm if it is slow for you as well. This helps rule out a problem with the user's local network. If it is slow for everyone, the server is likely under heavy load. This is not something support can fix directly. Please escalate to the development team so they can investigate the server's performance.

### I'm getting a security warning in my browser. Is it safe to continue?
**No.** Do not click past security warnings. A warning message almost always means the site's security certificate has expired. While the underlying data is likely fine, it's a security risk that must be fixed. Escalate to the development team immediately.
