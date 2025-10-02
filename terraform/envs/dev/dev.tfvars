project_name = "legacy-wepabb"
env          = "dev"
region       = "us-east-2"

vpc_cidr             = "10.42.0.0/16"
private_subnet_cidrs = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
public_subnet_cidrs  = ["10.42.240.0/24", "10.42.241.0/24"]

additional_ip_strategy = "secondary_ips" # or "multi_eni"
static_ips             = null            # or ["10.42.0.50", "10.42.0.51", "10.42.0.52", "10.42.0.53", "10.42.0.54"]

enable_scheduler = true
enable_rds_custom = false # Set to true when CEV/custom AMI is ready

ssm_allowed_iam_usernames = ["alice", "bob"]

s3_media_bucket = "dev-sqlserver-supportfiles-backups-and-iso-files"
sql_iso_key     = "media/SERVER_EVAL_x64FRE_en-us.iso"
sql_cu_key      = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"

rds_instance_class    = "db.m5.xlarge"
rds_allocated_storage = 100
