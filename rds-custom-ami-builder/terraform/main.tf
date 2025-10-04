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
}

# Data: Latest Windows Server 2019 AMI (RDS Custom compatible)
data "aws_ami" "windows_2019" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Data: Get SA password from SSM Parameter Store
data "aws_ssm_parameter" "sa_password" {
  name            = var.sa_password_ssm_path
  with_decryption = true
}

# Security Group for Builder Instance
resource "aws_security_group" "builder" {
  name        = "${var.env}-${var.project_name}-ami-builder-sg"
  description = "Security group for SQL Server AMI builder instance"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.env}-${var.project_name}-ami-builder-sg"
    env     = var.env
    project = var.project_name
  }
}

# Use default VPC for builder (temporary instance)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# IAM Role for Builder Instance
resource "aws_iam_role" "builder" {
  name = "${var.env}-${var.project_name}-ami-builder-role"

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
    Name    = "${var.env}-${var.project_name}-ami-builder-role"
    env     = var.env
    project = var.project_name
  }
}

# Attach SSM policy
resource "aws_iam_role_policy_attachment" "builder_ssm" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch policy
resource "aws_iam_role_policy_attachment" "builder_cloudwatch" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for S3 and SSM Parameter Store
resource "aws_iam_role_policy" "builder_custom" {
  name = "${var.env}-${var.project_name}-ami-builder-custom-policy"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
          "ssm:GetParameters"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter${var.sa_password_ssm_path}"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "builder" {
  name = "${var.env}-${var.project_name}-ami-builder-profile"
  role = aws_iam_role.builder.name

  tags = {
    Name    = "${var.env}-${var.project_name}-ami-builder-profile"
    env     = var.env
    project = var.project_name
  }
}

# Builder EC2 Instance
resource "aws_instance" "builder" {
  ami                    = data.aws_ami.windows_2019.id
  instance_type          = "m5.xlarge"
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.builder.id]
  iam_instance_profile   = aws_iam_instance_profile.builder.name

  # No public IP needed with SSM
  associate_public_ip_address = false

  # Larger root volume for SQL Server
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 150
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/install-sql-server.ps1", {
    s3_bucket   = var.s3_media_bucket
    sql_iso_key = var.sql_iso_key
    sql_cu_key  = var.sql_cu_key
    sa_password = data.aws_ssm_parameter.sa_password.value
  })

  tags = {
    Name    = "${var.env}-${var.project_name}-ami-builder"
    env     = var.env
    project = var.project_name
    purpose = "RDS Custom AMI Builder"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# CloudWatch Log Group for UserData logs
resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/ec2/${var.env}-${var.project_name}-ami-builder"
  retention_in_days = 7

  tags = {
    Name    = "${var.env}-${var.project_name}-ami-builder-logs"
    env     = var.env
    project = var.project_name
  }
}


