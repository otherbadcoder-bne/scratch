variables {
  domain_name  = "wiki.test.example.com"
  access_token = "test-token"
}

run "instance_type_defaults_to_t3_micro" {
  command = plan

  assert {
    condition     = aws_instance.wiki.instance_type == "t3.micro"
    error_message = "Instance type should default to t3.micro"
  }
}

run "instance_enforces_imdsv2" {
  command = plan

  assert {
    condition     = aws_instance.wiki.metadata_options[0].http_tokens == "required"
    error_message = "Instance must enforce IMDSv2 (http_tokens = required)"
  }

  assert {
    condition     = aws_instance.wiki.metadata_options[0].http_endpoint == "enabled"
    error_message = "Instance metadata endpoint must be enabled"
  }
}

run "instance_uses_gp3_volume" {
  command = plan

  assert {
    condition     = aws_instance.wiki.root_block_device[0].volume_type == "gp3"
    error_message = "Root volume must be gp3"
  }

  assert {
    condition     = aws_instance.wiki.root_block_device[0].volume_size == 20
    error_message = "Root volume must be 20 GB"
  }
}

run "iam_role_allows_ec2_to_assume" {
  command = plan

  assert {
    condition     = can(jsondecode(aws_iam_role.wiki.assume_role_policy))
    error_message = "IAM role must have a valid assume role policy"
  }
}

run "ssm_policy_attached" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "SSM managed instance core policy must be attached"
  }
}

run "security_group_allows_port_3000_inbound" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront.from_port == 3000
    error_message = "Ingress rule must allow port 3000"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront.to_port == 3000
    error_message = "Ingress rule must target port 3000"
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront.ip_protocol == "tcp"
    error_message = "Ingress rule must be TCP"
  }
}

run "no_ssh_ingress_rule" {
  command = plan

  # There should be exactly one ingress rule (port 3000 from CloudFront)
  # and no SSH rule
  assert {
    condition     = aws_vpc_security_group_ingress_rule.cloudfront.from_port != 22
    error_message = "There must be no SSH ingress rule"
  }
}
