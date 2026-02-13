# --- Scheduled stop/start for cost saving ---
# Stops the Wiki.js EC2 instance outside working hours (Mon-Fri 7am-7pm AEST).
# Uses EventBridge Scheduler -> SSM Automation (AWS-managed documents).

data "aws_region" "current" {}

# --- IAM Role for EventBridge Scheduler + SSM Automation ---

resource "aws_iam_role" "scheduler" {
  count = var.schedule_enabled ? 1 : 0
  name  = "${var.environment}-wiki-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "scheduler.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = {
    environment = var.environment
  }
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.schedule_enabled ? 1 : 0
  name  = "wiki-scheduler"
  role  = aws_iam_role.scheduler[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMAutomation"
        Effect = "Allow"
        Action = "ssm:StartAutomationExecution"
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:*:automation-definition/AWS-StopEC2Instances:*",
          "arn:aws:ssm:${data.aws_region.current.name}:*:automation-definition/AWS-StartEC2Instances:*",
        ]
      },
      {
        Sid    = "EC2StopStart"
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:StartInstances",
        ]
        Resource = aws_instance.wiki.arn
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.scheduler[0].arn
      },
    ]
  })
}

# --- EventBridge Schedules ---

resource "aws_scheduler_schedule" "wiki_stop" {
  count = var.schedule_enabled ? 1 : 0
  name  = "${var.environment}-wiki-stop"

  schedule_expression          = "cron(0 19 ? * MON-FRI *)"
  schedule_expression_timezone = "Australia/Brisbane"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      DocumentName = "AWS-StopEC2Instances"
      Parameters = {
        InstanceId           = [aws_instance.wiki.id]
        AutomationAssumeRole = [aws_iam_role.scheduler[0].arn]
      }
    })
  }
}

resource "aws_scheduler_schedule" "wiki_start" {
  count = var.schedule_enabled ? 1 : 0
  name  = "${var.environment}-wiki-start"

  schedule_expression          = "cron(0 5 ? * MON-FRI *)"
  schedule_expression_timezone = "Australia/Brisbane"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.scheduler[0].arn

    input = jsonencode({
      DocumentName = "AWS-StartEC2Instances"
      Parameters = {
        InstanceId           = [aws_instance.wiki.id]
        AutomationAssumeRole = [aws_iam_role.scheduler[0].arn]
      }
    })
  }
}
