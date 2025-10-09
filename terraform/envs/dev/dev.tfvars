project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# VPC Configuration
vpc_cidr             = "10.42.0.0/16"
private_subnet_cidrs = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
public_subnet_cidrs  = ["10.42.240.0/24", "10.42.241.0/24"]

# EC2 IP Configuration (6 total: 1 primary + 5 secondary)
additional_ip_strategy = "secondary_ips"
static_ips = [
  "10.42.0.60",
  "10.42.0.61",
  "10.42.0.62",
  "10.42.0.63",
  "10.42.0.64",
  "10.42.0.65"
]

# RDS Custom Configuration
# IMPORTANT: Set enable_rds_custom to true AFTER CEV is registered
enable_rds_custom = true
enable_scheduler  = true
dev_cev_version = "16.00.4195.2.dev-cev-20251007"
# SSM Access Control
ssm_allowed_iam_usernames = ["dev-brandon-leal","dev-nick-avaneas","dev-brandon-jerrell"]

# S3 Media Bucket
s3_media_bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
# sql_iso_key     = "media/SQLServer2022-x64-ENU-Dev.iso"
# sql_cu_key      = "media/sqlserver2022-kb5054531-x64_1f9436d6f4ae16354819cab42a6aef9292f1fc06.exe"

custom_rds_username = "sqladmin"
key_name="legacy_ec2"
# RDS Instance Configuration
rds_instance_class    = "db.m5.xlarge"
rds_allocated_storage = 900


