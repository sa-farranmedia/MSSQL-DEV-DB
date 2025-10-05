data "aws_ssm_parameter" "db_master_password" {
  name            = var.db_master_password_param_name
  with_decryption = true
}

# Security Group for RDS Custom
resource "aws_security_group" "rds_custom" {
  name        = "${var.env}-${var.project_name}-rds-sg"
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

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-sg"
  })
}

# DB Subnet Group
resource "aws_db_subnet_group" "rds_custom" {
  name       = "${var.env}-${var.project_name}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-subnet-group"
  })
}

resource "aws_iam_role" "rds_custom" {
  name = "AWSRDSCustomSQLServerRole-${var.env}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}
## Required policies for the EC2 host that backs RDS Custom
resource "aws_iam_role_policy_attachment" "rds_custom_instance_profile_policy" {
  role       = aws_iam_role.rds_custom.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSCustomInstanceProfileRolePolicy"
}
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.rds_custom.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
# Instance Profile for RDS Custom

resource "aws_iam_instance_profile" "rds_custom" {
  # MUST begin with AWSRDSCustom*
  name = "AWSRDSCustomSQLServerInstanceProfile-${var.env}"
  role = aws_iam_role.rds_custom.name
    tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-custom-profile"
  })
}
# RDS Custom DB Instance
# NOTE: Comment this out until CEV is created and registered
# Uncomment after running rds-custom-ami-builder workflow

resource "aws_db_instance" "rds_custom" {
  identifier     = "${var.env}-${var.project_name}-rds-custom"
  engine         = "custom-sqlserver-we"
  engine_version = @REPLACEME # Update with your CEV version
  auto_minor_version_upgrade  = false

  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  username            = var.db_master_username
  password            = data.aws_ssm_parameter.db_master_password.value
  kms_key_id          = aws_kms_key.rds_custom.arn

  db_subnet_group_name   = aws_db_subnet_group.rds_custom.name
  vpc_security_group_ids = [aws_security_group.rds_custom.id]
  publicly_accessible    = false

  # Custom Engine Version requires custom IAM role
  custom_iam_instance_profile = aws_iam_instance_profile.rds_custom.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = true
  final_snapshot_identifier = null

  # CloudWatch Logs exports (version dependent - may need adjustment)
  # enabled_cloudwatch_logs_exports = ["error", "agent"]

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-custom"
  })
}

# Scheduler Lambda Role
resource "aws_iam_role" "scheduler_lambda" {
  count = var.enable_scheduler ? 1 : 0
  name  = "${var.env}-${var.project_name}-scheduler-lambda-role"

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

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-scheduler-lambda-role"
  })
}

# Lambda Policy for RDS Actions
resource "aws_iam_role_policy" "scheduler_lambda" {
  count = var.enable_scheduler ? 1 : 0
  name  = "${var.env}-${var.project_name}-scheduler-lambda-policy"
  role  = aws_iam_role.scheduler_lambda[0].id

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
        Resource = "arn:aws:logs:${var.region}:*:*"
      }
    ]
  })
}

# CloudWatch Log Groups for Lambda Functions
resource "aws_cloudwatch_log_group" "start_lambda" {
  count             = var.enable_scheduler ? 1 : 0
  name              = "/aws/lambda/${var.env}-${var.project_name}-rds-start"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-start-logs"
  })
}

resource "aws_cloudwatch_log_group" "stop_lambda" {
  count             = var.enable_scheduler ? 1 : 0
  name              = "/aws/lambda/${var.env}-${var.project_name}-rds-stop"
  retention_in_days = 14

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-stop-logs"
  })
}

# Start Lambda Function
resource "aws_lambda_function" "start_rds" {
  count            = var.enable_scheduler ? 1 : 0
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${var.env}-${var.project_name}-rds-start"
  role             = aws_iam_role.scheduler_lambda[0].arn
  handler          = "handler.start_handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      DB_INSTANCE_ID = "${var.env}-${var.project_name}-rds-custom"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-start"
  })

  depends_on = [aws_cloudwatch_log_group.start_lambda]
}

# Stop Lambda Function
resource "aws_lambda_function" "stop_rds" {
  count            = var.enable_scheduler ? 1 : 0
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${var.env}-${var.project_name}-rds-stop"
  role             = aws_iam_role.scheduler_lambda[0].arn
  handler          = "handler.stop_handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime          = "python3.11"
  timeout          = 60

  environment {
    variables = {
      DB_INSTANCE_ID = "${var.env}-${var.project_name}-rds-custom"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-stop"
  })

  depends_on = [aws_cloudwatch_log_group.stop_lambda]
}

# Archive Lambda code
data "archive_file" "lambda_zip" {
  count       = var.enable_scheduler ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

# EventBridge Rule - Start weekdays at 1:00 PM UTC (6:00 AM MST)
resource "aws_cloudwatch_event_rule" "start_weekdays" {
  count               = var.enable_scheduler ? 1 : 0
  name                = "${var.env}-${var.project_name}-rds-start-weekdays"
  description         = "Start RDS Custom weekdays at 6:00 AM MST (1:00 PM UTC)"
  schedule_expression = "cron(0 13 ? * MON-FRI *)"

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-start-weekdays"
  })
}

# EventBridge Rule - Stop weeknights at 8:00 AM UTC (1:00 AM MST)
resource "aws_cloudwatch_event_rule" "stop_weeknights" {
  count               = var.enable_scheduler ? 1 : 0
  name                = "${var.env}-${var.project_name}-rds-stop-weeknights"
  description         = "Stop RDS Custom weeknights at 1:00 AM MST (8:00 AM UTC)"
  schedule_expression = "cron(0 8 ? * TUE-FRI *)"

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-stop-weeknights"
  })
}

# EventBridge Rule - Stop weekend at 12:00 AM Saturday UTC (5:00 PM Friday MST)
resource "aws_cloudwatch_event_rule" "stop_weekend" {
  count               = var.enable_scheduler ? 1 : 0
  name                = "${var.env}-${var.project_name}-rds-stop-weekend"
  description         = "Stop RDS Custom for weekend at 5:00 PM Fri MST (12:00 AM Sat UTC)"
  schedule_expression = "cron(0 0 ? * SAT *)"

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-rds-stop-weekend"
  })
}

# EventBridge Targets
resource "aws_cloudwatch_event_target" "start_weekdays" {
  count     = var.enable_scheduler ? 1 : 0
  rule      = aws_cloudwatch_event_rule.start_weekdays[0].name
  target_id = "StartRDSLambda"
  arn       = aws_lambda_function.start_rds[0].arn
}

resource "aws_cloudwatch_event_target" "stop_weeknights" {
  count     = var.enable_scheduler ? 1 : 0
  rule      = aws_cloudwatch_event_rule.stop_weeknights[0].name
  target_id = "StopRDSLambda"
  arn       = aws_lambda_function.stop_rds[0].arn
}

resource "aws_cloudwatch_event_target" "stop_weekend" {
  count     = var.enable_scheduler ? 1 : 0
  rule      = aws_cloudwatch_event_rule.stop_weekend[0].name
  target_id = "StopRDSLambda"
  arn       = aws_lambda_function.stop_rds[0].arn
}

# Lambda Permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_start" {
  count         = var.enable_scheduler ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_rds[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_weekdays[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge_stop_weeknights" {
  count         = var.enable_scheduler ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_rds[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_weeknights[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge_stop_weekend" {
  count         = var.enable_scheduler ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridgeWeekend"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_rds[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_weekend[0].arn
}


