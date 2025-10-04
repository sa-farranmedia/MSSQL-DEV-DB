# Data source for latest Windows Server 2022 AMI
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for EC2
resource "aws_security_group" "ec2" {
  name        = "${var.env}-${var.project_name}-ec2-sg"
  description = "Security group for Windows EC2 instance"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-ec2-sg"
  })
}

# IAM Role for EC2
resource "aws_iam_role" "ec2" {
  name = "${var.env}-${var.project_name}-ec2-role"

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

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-ec2-role"
  })
}

# Attach SSM Managed Instance Core Policy
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch Agent Policy
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom Policy for S3 and SSM Parameter Store Access
resource "aws_iam_role_policy" "ec2_custom" {
  name = "${var.env}-${var.project_name}-ec2-custom-policy"
  role = aws_iam_role.ec2.id

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
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.env}/${var.project_name}/*"
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
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.env}-${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-ec2-profile"
  })
}

# EC2 Instance
resource "aws_instance" "windows" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = "m6i.2xlarge"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  private_ip             = var.primary_private_ip

  # No public IP
  associate_public_ip_address = false

  # IMDSv2 required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # EBS encryption
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.ps1", {
    project_name = var.project_name
    env          = var.env
  })

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-ec2"
  })

  lifecycle {
    ignore_changes = [user_data]
  }
}

# Wait before assigning secondary IPs
resource "time_sleep" "wait_for_instance" {
  depends_on = [aws_instance.windows]

  create_duration = "30s"
}

# Assign secondary IPs using AWS CLI (null_resource)
resource "null_resource" "assign_secondary_ips" {
  depends_on = [time_sleep.wait_for_instance]

  triggers = {
    instance_id   = aws_instance.windows.id
    secondary_ips = join(",", var.secondary_ips)
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Get primary ENI ID
      ENI_ID=$(aws ec2 describe-instances \
        --instance-ids ${aws_instance.windows.id} \
        --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
        --output text \
        --region ${var.region})

      # Assign secondary IPs with --allow-reassignment
      aws ec2 assign-private-ip-addresses \
        --network-interface-id $ENI_ID \
        --private-ip-addresses ${join(" ", var.secondary_ips)} \
        --allow-reassignment \
        --region ${var.region}

      echo "Assigned secondary IPs: ${join(", ", var.secondary_ips)}"
    EOT
  }
}


