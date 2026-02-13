variables {
  domain_name  = "wiki.test.example.com"
  access_token = "test-token"
}

run "vpc_has_dns_enabled" {
  command = plan

  assert {
    condition     = aws_vpc.main.enable_dns_support == true
    error_message = "VPC must have DNS support enabled"
  }

  assert {
    condition     = aws_vpc.main.enable_dns_hostnames == true
    error_message = "VPC must have DNS hostnames enabled"
  }
}

run "vpc_uses_correct_cidr" {
  command = plan

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR should default to 10.0.0.0/16"
  }
}

run "creates_three_public_subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Expected 3 public subnets"
  }
}

run "creates_three_private_subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Expected 3 private subnets"
  }
}

run "public_subnets_auto_assign_public_ip" {
  command = plan

  assert {
    condition     = aws_subnet.public[0].map_public_ip_on_launch == true
    error_message = "Public subnets must auto-assign public IPs"
  }
}

run "private_subnets_do_not_auto_assign_public_ip" {
  command = plan

  assert {
    condition     = aws_subnet.private[0].map_public_ip_on_launch == false
    error_message = "Private subnets must not auto-assign public IPs"
  }
}

run "all_resources_tagged_with_environment" {
  command = plan

  assert {
    condition     = aws_vpc.main.tags["environment"] == "shared-services"
    error_message = "VPC must be tagged with environment"
  }

  assert {
    condition     = aws_internet_gateway.main.tags["environment"] == "shared-services"
    error_message = "IGW must be tagged with environment"
  }
}
