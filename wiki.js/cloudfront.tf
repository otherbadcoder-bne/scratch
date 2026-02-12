# Managed cache policy: CachingDisabled
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Managed origin request policy: AllViewer
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# Response headers policy — security headers (HSTS, X-Content-Type-Options, etc.)
resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${var.environment}-wiki-security-headers"
  comment = "Security headers for Wiki.js"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    content_security_policy {
      content_security_policy = "frame-ancestors 'none'"
      override                = true
    }
  }
}

#trivy:ignore:AWS-0011 WAF is costly for this implementation. Ideally would front via CloudFlare but work needs to be done to move out of AWS R53.
#checkov:skip=CKV_AWS_374 While current expected access is from Oceania, it's not confirmed.
#checkov:skip=CKV_AWS_86 Access logging is unnecessary for the small intended use - will reconsider in 6 months and if the server performance hammers the operating parameters
#checkov:skip=CKV_AWS_310 Origin Failover - chances are unlikely we will use this, not a HA config, thanks for the suggestion but no thank you
#checkov:skip=CKV_AWS_305 Private access which will be linked, root pathing isn't a worry since we understand the use of the service
#checkov:skip=CKV_AWS_68 See top Trivy recommendation for same understanding
#checkov:skip=CKV2_AWS_47 Appreciate the suggestion but not using a WAF implementation for this - see above(s)
resource "aws_cloudfront_distribution" "wiki" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Wiki.js — ${var.domain_name}"
  aliases         = [var.domain_name]

  origin {
    domain_name = aws_instance.wiki.public_dns
    origin_id   = "wiki-ec2"

    custom_origin_config {
      http_port              = 3000
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "wiki-ec2"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.wiki.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.environment}-wiki-cdn"
    environment = var.environment
  }
}
