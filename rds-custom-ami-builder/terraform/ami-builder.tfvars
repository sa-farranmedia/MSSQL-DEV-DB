project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# S3 Media Configuration
s3_media_bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
sql_iso_key     = "media/SQLServer2022-x64-ENU-Dev.iso"
sql_cu_key      = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"

# SA Password from SSM Parameter Store
sa_password_ssm_path = "/dev/legacy-webapp/rds/sa-password"


