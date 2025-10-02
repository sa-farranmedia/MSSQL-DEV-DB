# Fetch latest Windows Server 2022 AMI
data "aws_ssm_parameter" "windows_2022_ami" {
  name = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
}

# Security Group for EC2
resource "aws_security_group" "ec2" {
  name_prefix = "${var.env}-${var.project_name}-ec2-"
  description = "Security group for Windows EC2 instance"
  vpc_id      = var.vpc_id

  # Allow all outbound (for VPC endpoints, S3, etc.)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-${var.project_name}-ec2-sg"
  }
}

# IAM Role for EC2
resource "aws_iam_role" "ec2" {
  name_prefix = "${var.env}-${var.project_name}-ec2-"

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
    Name = "${var.env}-${var.project_name}-ec2-role"
  }
}

# IAM Policy for SSM and S3 access
resource "aws_iam_role_policy" "ec2" {
  name_prefix = "${var.env}-${var.project_name}-ec2-"
  role        = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/ec2/${var.env}-${var.project_name}*"
      }
    ]
  })
}

# Attach SSM Managed Instance Core policy
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name_prefix = "${var.env}-${var.project_name}-ec2-"
  role        = aws_iam_role.ec2.name

  tags = {
    Name = "${var.env}-${var.project_name}-ec2-profile"
  }
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/aws/ec2/${var.env}-${var.project_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.env}-${var.project_name}-logs"
  }
}

# Validate ENI/IP constraints for m6i.2xlarge
locals {
  max_enis_for_instance = 4
  max_ips_per_eni       = 15

  # Determine ENI/IP allocation based on strategy
  use_secondary_ips = var.additional_ip_strategy == "secondary_ips"
  use_multi_eni     = var.additional_ip_strategy == "multi_eni"

  # For secondary_ips: 1 ENI, 5 secondary IPs on primary ENI
  # For multi_eni: distribute 5 IPs across up to 3 additional ENIs (total 4 ENIs)
  num_additional_enis = local.use_multi_eni ? 3 : 0
  total_enis          = 1 + local.num_additional_enis

  # Validation
  eni_count_valid = local.total_enis <= local.max_enis_for_instance
  ip_count_valid  = local.use_secondary_ips ? (5 <= local.max_ips_per_eni) : true

  # Generate or use provided static IPs
  static_ip_list = var.static_ips != null ? var.static_ips : []
}

# Validation checks
resource "null_resource" "validate_eni_limits" {
  count = local.eni_count_valid ? 0 : 1

  provisioner "local-exec" {
    command = "echo 'ERROR: Requested ENI count (${local.total_enis}) exceeds m6i.2xlarge limit (${local.max_enis_for_instance})' && exit 1"
  }
}

resource "null_resource" "validate_ip_limits" {
  count = local.ip_count_valid ? 0 : 1

  provisioner "local-exec" {
    command = "echo 'ERROR: Requested IP count exceeds per-ENI limit (${local.max_ips_per_eni})' && exit 1"
  }
}

# Windows EC2 Instance
resource "aws_instance" "windows" {
  ami                    = data.aws_ssm_parameter.windows_2022_ami.value
  instance_type          = "m6i.2xlarge"
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # IMDSv2 required
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  # EBS encryption
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 100
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.ps1", {
    log_group_name  = aws_cloudwatch_log_group.ec2.name
    region          = var.region
    s3_media_bucket = var.s3_media_bucket
  })

  tags = {
    Name = "${var.env}-${var.project_name}-ec2"
  }

  depends_on = [
    null_resource.validate_eni_limits,
    null_resource.validate_ip_limits
  ]
}

# Strategy A: Secondary IPs on primary ENI
resource "aws_network_interface" "primary" {
  count = local.use_secondary_ips ? 1 : 0

  subnet_id       = var.private_subnet_ids[0]
  security_groups = [aws_security_group.ec2.id]

  # Assign 5 secondary private IPs
  private_ips_count = 5
  private_ips       = length(local.static_ip_list) == 5 ? local.static_ip_list : null

  attachment {
    instance     = aws_instance.windows.id
    device_index = 0
  }

  tags = {
    Name = "${var.env}-${var.project_name}-primary-eni"
  }
}

# Strategy B: Additional ENIs
resource "aws_network_interface" "additional" {
  count = local.use_multi_eni ? local.num_additional_enis : 0

  subnet_id       = var.private_subnet_ids[0]
  security_groups = [aws_security_group.ec2.id]

  # Distribute IPs: 2, 2, 1 across 3 ENIs
  private_ips_count = count.index < 2 ? 2 : 1
  private_ips = length(local.static_ip_list) == 5 ? (
    count.index == 0 ? [local.static_ip_list[0], local.static_ip_list[1]] :
    count.index == 1 ? [local.static_ip_list[2], local.static_ip_list[3]] :
    [local.static_ip_list[4]]
  ) : null

  tags = {
    Name = "${var.env}-${var.project_name}-eni-${count.index + 1}"
  }
}

resource "aws_network_interface_attachment" "additional" {
  count = local.use_multi_eni ? local.num_additional_enis : 0

  instance_id          = aws_instance.windows.id
  network_interface_id = aws_network_interface.additional[count.index].id
  device_index         = count.index + 1
}
