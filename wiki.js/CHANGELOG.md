# Changelog

All notable changes to the Wiki.js infrastructure project are documented here.

## 2026-02-13

### Added
- **Scheduled stop/start** — EventBridge Scheduler stops the EC2 instance at 7pm AEST and starts it at 5am AEST on weekdays (covers 8am NZST for NZ users). Uses SSM Automation (`AWS-StopEC2Instances` / `AWS-StartEC2Instances`) with no Lambda required.
- `schedule_enabled` variable to toggle the stop/start schedule (default: `true`).
- **CloudFront Function access gate** — secret path-prefix "knock" that sets a session cookie, preventing unauthorised discovery of the Wiki.js instance. Requests without the token receive a generic 403.
- `access_token` variable (`sensitive`) to configure the secret prefix.

### Changed
- CloudFront `default_cache_behavior` now includes a `viewer-request` function association for the access gate.

## 2026-02-12

### Added
- Full Terraform deployment: VPC, EC2, CloudFront, ACM, SSM, security groups.
- Pre-commit hooks: terraform fmt/validate, tflint, terraform-docs, trivy, checkov, gitleaks, infracost.
- Terraform test suite (`cloudfront.tftest.hcl`, `ec2.tftest.hcl`, `vpc.tftest.hcl`).
- Response headers policy with HSTS, X-Frame-Options, X-Content-Type-Options, XSS-Protection, Referrer-Policy, and CSP.
- Infracost breakdown auto-generated in README.

### Security decisions
- **No WAF** — AWS WAF adds ~$6-10/month minimum (WebACL + rule groups) which nearly doubles the baseline cost of this deployment (~$12/month). For a small internal wiki behind Google OAuth + the access gate, the cost-benefit does not justify it. This will be reconsidered if the wiki becomes more widely used or handles sensitive data.
- **No access logging** — CloudFront access logging is unnecessary for the current small-scale internal use. Will be reconsidered in 6 months.

## 2026-02-11

### Added
- Initial project scaffold and repository setup.
- Pre-commit framework configuration.
