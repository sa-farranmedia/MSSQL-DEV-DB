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

# Data: Windows Server 2019 + SQL Server 2022 Web (License-Included) AMI
data "aws_ami" "windows_2019" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-SQL_2022_Web-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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

resource "aws_iam_role_policy_attachment" "builder_ssm_core" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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
  key_name = var.key_name
  # No public IP needed with SSM
  associate_public_ip_address = var.builder_public

  # Larger root volume for SQL Server
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 150
    encrypted             = true
    delete_on_termination = true
  }


  tags = {
    Name    = "${var.env}-${var.project_name}-ami-builder"
    env     = var.env
    project = var.project_name
    purpose = "RDS Custom AMI Builder"
  }
}

# Optional: SSM Interface VPC Endpoints for private builds (toggle with var.create_ssm_endpoints)
resource "aws_security_group" "vpce_ssm" {
  count       = var.create_ssm_endpoints ? 1 : 0
  name        = "${var.env}-${var.project_name}-vpce-ssm-sg"
  description = "VPCE SG for SSM endpoints (allow 443 from builder SG)"
  vpc_id      = data.aws_vpc.default.id
  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.vpc_cidr]  # ← Change to CIDR instead of security group
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.env}-${var.project_name}-vpce-ssm-sg"
    env     = var.env
    project = var.project_name
  }
}

# Allow HTTPS from builder SG to the VPCE SG (provider v5 pattern)
resource "aws_vpc_security_group_ingress_rule" "vpce_https_from_builder" {
  count                         = var.create_ssm_endpoints ? 1 : 0
  security_group_id             = aws_security_group.vpce_ssm[0].id
  ip_protocol                   = "tcp"
  from_port                     = 443
  to_port                       = 443
  referenced_security_group_id  = aws_security_group.builder.id
}

locals {
  ssm_services = var.create_ssm_endpoints ? [
    "ssm",
    "ssmmessages",
    "ec2messages"
  ] : []
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = toset(local.ssm_services)
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default.ids
  security_group_ids  = [aws_security_group.vpce_ssm[0].id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.env}-${var.project_name}-vpce-${each.key}"
    env     = var.env
    project = var.project_name
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

output "builder_instance_id" {
  value = aws_instance.builder.id
}

output "builder_public_ip" {
  value       = aws_instance.builder.public_ip
  description = "Public IP present only when var.builder_public = true"
}
