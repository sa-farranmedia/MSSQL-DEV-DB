# IAM Role for RDS Custom
resource "aws_iam_role" "rds_custom" {
  name_prefix = "${var.env}-${var.project_name}-rds-custom-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.env}-${var.project_name}-rds-custom-role"
  }
}

# IAM Policy for RDS Custom
resource "aws_iam_role_policy" "rds_custom" {
  name_prefix = "${var.env}-${var.project_name}-rds-custom-"
  role        = aws_iam_role.rds_custom.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "ec2:CreateTags",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute"
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
          "arn:aws:s3:::do-not-delete-rds-custom-*",
          "arn:aws:s3:::do-not-delete-rds-custom-*/*"
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
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/rds/custom/*"
      }
    ]
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "rds_custom" {
  name_prefix = "${var.env}-${var.project_name}-rds-"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.env}-${var.project_name}-rds-subnet-group"
  }
}

# Security Group for RDS Custom
resource "aws_security_group" "rds_custom" {
  name_prefix = "${var.env}-${var.project_name}-rds-"
  description = "Security group for RDS Custom SQL Server"
  vpc_id      = var.vpc_id

  ingress {
    description = "SQL Server from VPC"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.env}-${var.project_name}-rds-sg"
  }
}

# Commented RDS Custom Engine Version (CEV)
# Uncomment when custom AMI is ready
# resource "aws_rds_custom_db_engine_version" "sqlserver" {
#   engine                = "custom-sqlserver-ee"
#   engine_version        = "15.00.4335.1.my-cev-v1"
#   database_installation_files_s3_bucket_name = "my-cev-bucket"
#   database_installation_files_s3_prefix      = "cev/"
#   manifest = file("${path.module}/cev-manifest.json")
#
#   tags = {
#     Name = "${var.env}-${var.project_name}-cev"
#   }
# }

# Commented RDS Custom DB Instance
# Uncomment when CEV is available
# resource "aws_db_instance" "rds_custom" {
#   count = var.enable_rds_custom ? 1 : 0
#
#   identifier        = "${var.env}-${var.project_name}-sqlserver"
#   engine            = aws_rds_custom_db_engine_version.sqlserver.engine
#   engine_version    = aws_rds_custom_db_engine_version.sqlserver.engine_version
#   instance_class    = var.rds_instance_class
#   allocated_storage = var.rds_allocated_storage
#
#   db_subnet_group_name   = aws_db_subnet_group.rds_custom.name
#   vpc_security_group_ids = [aws_security_group.rds_custom.id]
#
#   username = "admin"
#   password = random_password.rds_master.result
#
#   backup_retention_period = 7
#   skip_final_snapshot     = true
#
#   custom_iam_instance_profile = aws_iam_role.rds_custom.arn
#
#   tags = {
#     Name = "${var.env}-${var.project_name}-rds-custom"
#   }
# }

# Generate random password for RDS
resource "random_password" "rds_master" {
  length  = 24
  special = true
}

# Store password in SSM Parameter Store
resource "aws_ssm_parameter" "rds_password" {
  name        = "/${var.env}/${var.project_name}/rds/master-password"
  description = "RDS Custom master password"
  type        = "SecureString"
  value       = random_password.rds_master.result

  tags = {
    Name = "${var.env}-${var.project_name}-rds-password"
  }
}

# Lambda execution role
resource "aws_iam_role" "scheduler_lambda" {
  count = var.enable_scheduler ? 1 : 0

  name_prefix = "${var.env}-${var.project_name}-scheduler-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.env}-${var.project_name}-scheduler-role"
  }
}

# Lambda policy for RDS start/stop
resource "aws_iam_role_policy" "scheduler_lambda" {
  count = var.enable_scheduler ? 1 : 0

  name_prefix = "${var.env}-${var.project_name}-scheduler-"
  role        = aws_iam_role.scheduler_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:DescribeDBInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.env}-${var.project_name}-scheduler*"
      }
    ]
  })
}

# Lambda function for scheduler
resource "aws_lambda_function" "scheduler" {
  count = var.enable_scheduler ? 1 : 0

  filename         = data.archive_file.scheduler_lambda[0].output_path
  function_name    = "${var.env}-${var.project_name}-scheduler"
  role             = aws_iam_role.scheduler_lambda[0].arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.scheduler_lambda[0].output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      DB_INSTANCE_IDENTIFIER = "${var.env}-${var.project_name}-sqlserver"
      REGION                 = var.region
    }
  }

  tags = {
    Name = "${var.env}-${var.project_name}-scheduler-lambda"
  }
}

# Package Lambda function
data "archive_file" "scheduler_lambda" {
  count = var.enable_scheduler ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/scheduler.zip"
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "scheduler_lambda" {
  count = var.enable_scheduler ? 1 : 0

  name              = "/aws/lambda/${aws_lambda_function.scheduler[0].function_name}"
  retention_in_days = 7

  tags = {
    Name = "${var.env}-${var.project_name}-scheduler-logs"
  }
}

# EventBridge rule: Start weekdays at 1:00 PM UTC (6:00 AM MST)
resource "aws_cloudwatch_event_rule" "start_weekdays" {
  count = var.enable_scheduler ? 1 : 0

  name                = "${var.env}-${var.project_name}-start-weekdays"
  description         = "Start RDS Custom SQL Server on weekdays"
  schedule_expression = "cron(0 13 ? * MON-FRI *)"

  tags = {
    Name = "${var.env}-${var.project_name}-start-rule"
  }
}

# EventBridge target for start rule
resource "aws_cloudwatch_event_target" "start_weekdays" {
  count = var.enable_scheduler ? 1 : 0

  rule      = aws_cloudwatch_event_rule.start_weekdays[0].name
  target_id = "StartRDSLambda"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "start"
  })
}

# Lambda permission for start rule
resource "aws_lambda_permission" "start_weekdays" {
  count = var.enable_scheduler ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeStart"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_weekdays[0].arn
}

# EventBridge rule: Stop weeknights at 8:00 AM UTC (1:00 AM MST)
resource "aws_cloudwatch_event_rule" "stop_weeknights" {
  count = var.enable_scheduler ? 1 : 0

  name                = "${var.env}-${var.project_name}-stop-weeknights"
  description         = "Stop RDS Custom SQL Server on weeknights"
  schedule_expression = "cron(0 8 ? * TUE-FRI *)"

  tags = {
    Name = "${var.env}-${var.project_name}-stop-weeknights-rule"
  }
}

# EventBridge target for stop weeknights
resource "aws_cloudwatch_event_target" "stop_weeknights" {
  count = var.enable_scheduler ? 1 : 0

  rule      = aws_cloudwatch_event_rule.stop_weeknights[0].name
  target_id = "StopRDSLambda"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "stop"
  })
}

# Lambda permission for stop weeknights
resource "aws_lambda_permission" "stop_weeknights" {
  count = var.enable_scheduler ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeStopWeeknights"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_weeknights[0].arn
}

# EventBridge rule: Stop weekend at midnight UTC Saturday
resource "aws_cloudwatch_event_rule" "stop_weekend" {
  count = var.enable_scheduler ? 1 : 0

  name                = "${var.env}-${var.project_name}-stop-weekend"
  description         = "Stop RDS Custom SQL Server on Saturday"
  schedule_expression = "cron(0 0 ? * SAT *)"

  tags = {
    Name = "${var.env}-${var.project_name}-stop-weekend-rule"
  }
}

# EventBridge target for stop weekend
resource "aws_cloudwatch_event_target" "stop_weekend" {
  count = var.enable_scheduler ? 1 : 0

  rule      = aws_cloudwatch_event_rule.stop_weekend[0].name
  target_id = "StopRDSLambdaWeekend"
  arn       = aws_lambda_function.scheduler[0].arn

  input = jsonencode({
    action = "stop"
  })
}

# Lambda permission for stop weekend
resource "aws_lambda_permission" "stop_weekend" {
  count = var.enable_scheduler ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridgeStopWeekend"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scheduler[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_weekend[0].arn
}
