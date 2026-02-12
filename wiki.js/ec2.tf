# --- IAM Role for SSM ---

resource "aws_iam_role" "wiki" {
  name = "${var.environment}-wiki-ec2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.wiki.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "wiki" {
  name = "${var.environment}-wiki-ec2"
  role = aws_iam_role.wiki.name
}

# --- Security Group ---

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "wiki" {
  name        = "${var.environment}-wiki"
  description = "Allow CloudFront to reach Wiki.js on port 3000"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-wiki-sg"
    environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  security_group_id = aws_security_group.wiki.id
  description       = "Wiki.js from CloudFront"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  from_port         = 3000
  to_port           = 3000
  ip_protocol       = "tcp"
}

#trivy:ignore:AWS-0104 This will most likely be accessible from anywhere so we're less worried about egress vulnerabilities
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.wiki.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Amazon Linux 2023 AMI ---

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- EC2 Instance ---

#trivy:ignore:AWS-0131 This will be documentation for private use and not anything PII or the like. Additionally if there's an issue with an encrypted volume its harder to work with.
#checkov:skip=CKV_AWS_135 This is a small host so EBS Optomised instance class, not expecting that level of throughput also no need to pay for that
#checkov:skip=CKV_AWS_126 Detailed monitoring costs money - not needed - see above two comments
resource "aws_instance" "wiki" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.wiki.name
  vpc_security_group_ids = [aws_security_group.wiki.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tftpl", {
    docker_compose_yml = file("${path.module}/docker-compose.yml")
  }))

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name        = "${var.environment}-wiki"
    environment = var.environment
  }
}
