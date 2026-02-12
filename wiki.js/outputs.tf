# --- DNS records to create in the other account's Route53 ---

output "acm_validation_records" {
  description = "Create these DNS records to validate the ACM certificate"
  value = {
    for dvo in aws_acm_certificate.wiki.domain_validation_options : dvo.domain_name => {
      type  = dvo.resource_record_type
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
    }
  }
}

output "cloudfront_domain_name" {
  description = "Create a CNAME or Route53 alias from var.domain_name to this value"
  value       = aws_cloudfront_distribution.wiki.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.wiki.id
}

output "instance_id" {
  description = "EC2 instance ID — connect with: aws ssm start-session --target <id>"
  value       = aws_instance.wiki.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
