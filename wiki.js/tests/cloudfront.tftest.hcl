variables {
  domain_name = "wiki.test.example.com"
}

run "cloudfront_redirects_to_https" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.wiki.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "CloudFront must redirect HTTP to HTTPS"
  }
}

run "cloudfront_allows_all_http_methods" {
  command = plan

  assert {
    condition     = length(aws_cloudfront_distribution.wiki.default_cache_behavior[0].allowed_methods) == 7
    error_message = "CloudFront must allow all 7 HTTP methods (GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE)"
  }
}

run "cloudfront_uses_custom_domain" {
  command = plan

  assert {
    condition     = contains(aws_cloudfront_distribution.wiki.aliases, "wiki.test.example.com")
    error_message = "CloudFront must use the provided domain name as an alias"
  }
}

run "cloudfront_origin_uses_port_3000" {
  command = plan

  assert {
    condition     = one(aws_cloudfront_distribution.wiki.origin).custom_origin_config[0].http_port == 3000
    error_message = "CloudFront origin must connect to port 3000"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.wiki.origin).custom_origin_config[0].origin_protocol_policy == "http-only"
    error_message = "CloudFront origin must use HTTP-only (TLS terminates at CloudFront)"
  }
}

run "cloudfront_uses_tls_1_2_minimum" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.wiki.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "CloudFront must enforce TLS 1.2 minimum"
  }
}

run "cloudfront_has_response_headers_policy" {
  command = plan

  assert {
    condition     = aws_cloudfront_response_headers_policy.security.security_headers_config[0].strict_transport_security[0].access_control_max_age_sec == 31536000
    error_message = "HSTS max-age must be 1 year (31536000 seconds)"
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.security.security_headers_config[0].frame_options[0].frame_option == "DENY"
    error_message = "X-Frame-Options must be DENY"
  }
}

run "acm_cert_uses_dns_validation" {
  command = plan

  assert {
    condition     = aws_acm_certificate.wiki.validation_method == "DNS"
    error_message = "ACM certificate must use DNS validation"
  }

  assert {
    condition     = aws_acm_certificate.wiki.domain_name == "wiki.test.example.com"
    error_message = "ACM certificate must be for the provided domain name"
  }
}
