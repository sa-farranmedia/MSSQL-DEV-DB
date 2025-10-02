terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Name    = "${var.env}-${var.project_name}-ami-builder"
      env     = var.env
      project = var.project_name
      purpose = "rds-custom-ami-builder"
    }
  }
}

# Data source: Latest Windows Server 2019 (RDS Custom requires 2019 or 2022)
data "aws_ssm_parameter" "windows_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-Base"
}

# Security Group for AMI Builder
resource "aws_security_group" "ami_builder" {
  name_prefix = "${var.env}-${var.project_name}-ami-builder-"
  description = "Security group for RDS Custom AMI builder"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-${var.project_name}-ami-builder-sg"
  }
}

# IAM Role for AMI Builder
resource "aws_iam_role" "ami_builder" {
  name_prefix = "${var.env}-${var.project_name}-ami-builder-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.env}-${var.project_name}-ami-builder-role"
  }
}

# IAM Policy for AMI Builder
resource "aws_iam_role_policy" "ami_builder" {
  name_prefix = "${var.env}-${var.project_name}-ami-builder-"
  role        = aws_iam_role.ami_builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:*",
          "ec2messages:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_media_bucket}",
          "arn:aws:s3:::${var.s3_media_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.env}/${var.project_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/rds-custom/ami-builder*"
      }
    ]
  })
}

# Attach SSM policy
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ami_builder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile
resource "aws_iam_instance_profile" "ami_builder" {
  name_prefix = "${var.env}-${var.project_name}-ami-builder-"
  role        = aws_iam_role.ami_builder.name

  tags = {
    Name = "${var.env}-${var.project_name}-ami-builder-profile"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ami_builder" {
  name              = "/aws/rds-custom/ami-builder"
  retention_in_days = 7

  tags = {
    Name = "${var.env}-${var.project_name}-ami-builder-logs"
  }
}

# Generate SA password
resource "random_password" "sa_password" {
  length  = 32
  special = true
}

# Store SA password in SSM
resource "aws_ssm_parameter" "sa_password" {
  name        = "/${var.env}/${var.project_name}/sql-server/sa-password"
  description = "SQL Server SA password for RDS Custom AMI"
  type        = "SecureString"
  value       = random_password.sa_password.result

  tags = {
    Name = "${var.env}-${var.project_name}-sa-password"
  }
}

# AMI Builder Instance
resource "aws_instance" "ami_builder" {
  ami                    = data.aws_ssm_parameter.windows_ami.value
  instance_type          = var.builder_instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ami_builder.id]
  iam_instance_profile   = aws_iam_instance_profile.ami_builder.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.builder_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  user_data = templatefile("${path.module}/install-sql-server.ps1", {
    region               = var.region
    s3_media_bucket      = var.s3_media_bucket
    sql_iso_key          = var.sql_iso_key
    sql_cu_key           = var.sql_cu_key
    sql_version          = var.sql_version
    sql_edition          = var.sql_edition
    sql_instance_name    = var.sql_instance_name
    sql_collation        = var.sql_collation
    sa_password_param    = aws_ssm_parameter.sa_password.name
    log_group_name       = aws_cloudwatch_log_group.ami_builder.name
    env                  = var.env
    project_name         = var.project_name
  })

  tags = {
    Name = "${var.env}-${var.project_name}-ami-builder"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Outputs
output "builder_instance_id" {
  description = "AMI Builder instance ID"
  value       = aws_instance.ami_builder.id
}

output "builder_private_ip" {
  description = "AMI Builder private IP"
  value       = aws_instance.ami_builder.private_ip
}

output "sa_password_ssm_parameter" {
  description = "SSM Parameter Store path for SA password"
  value       = aws_ssm_parameter.sa_password.name
}

output "ssm_connect_command" {
  description = "Command to connect via SSM"
  value       = "aws ssm start-session --target ${aws_instance.ami_builder.id} --region ${var.region}"
}
