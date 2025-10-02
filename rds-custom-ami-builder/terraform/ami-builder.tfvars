project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# Use VPC and subnet from main project
# Get these from: cd ../../terraform && terraform output
vpc_id    = "vpc-0f7f399bc0d6a442e"  # Replace with actual VPC ID
subnet_id = "subnet-0dbaef189ee20fcd2"  # Replace with actual private subnet ID

# SQL Server media in S3
s3_media_bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
sql_iso_key     = "media/SERVER_EVAL_x64FRE_en-us.iso"
sql_cu_key      = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"

# SQL Server configuration
sql_version       = "2022"
sql_edition       = "Enterprise"
sql_instance_name = "MSSQLSERVER"
sql_collation     = "SQL_Latin1_General_CP1_CI_AS"

# Builder instance config
builder_instance_type = "m5.xlarge"
builder_volume_size   = 150
