data "aws_caller_identity" "current" {}

resource "aws_kms_key" "rds_custom" {
  description                         = "CMK for RDS Custom SQL Server (dev)"
  key_usage                           = "ENCRYPT_DECRYPT"
  customer_master_key_spec            = "SYMMETRIC_DEFAULT"
  enable_key_rotation                 = true

  # Add explicit policy for RDS Custom
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow RDS Custom to use the key"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "rds.us-east-2.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "rds_custom" {
  name          = "alias/rds-custom-dev"
  target_key_id = aws_kms_key.rds_custom.key_id
}

# Let the EC2 role (instance profile) use the key
resource "aws_iam_role_policy" "rds_custom_kms_use" {
  role = aws_iam_role.rds_custom.name
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey"],
      Resource = aws_kms_key.rds_custom.arn
    }]
  })
}