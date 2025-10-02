variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "legacy-wepabb"
}

variable "env" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.42.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (must span 3 AZs)"
  type        = list(string)
  default     = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (must span 2 AZs)"
  type        = list(string)
  default     = ["10.42.240.0/24", "10.42.241.0/24"]
}

variable "additional_ip_strategy" {
  description = "Strategy for additional private IPs: 'secondary_ips' or 'multi_eni'"
  type        = string
  default     = "secondary_ips"

  validation {
    condition     = contains(["secondary_ips", "multi_eni"], var.additional_ip_strategy)
    error_message = "additional_ip_strategy must be either 'secondary_ips' or 'multi_eni'."
  }
}

variable "static_ips" {
  description = "List of 5 static private IPs to assign, or null for auto-assignment"
  type        = list(string)
  default     = null

  validation {
    condition     = var.static_ips == null || length(var.static_ips) == 5
    error_message = "static_ips must be null or a list of exactly 5 IP addresses."
  }
}

variable "enable_scheduler" {
  description = "Enable RDS Custom start/stop scheduler"
  type        = bool
  default     = true
}

variable "ssm_allowed_iam_usernames" {
  description = "List of IAM usernames allowed to SSM to instances"
  type        = list(string)
  default     = []
}

variable "s3_media_bucket" {
  description = "S3 bucket containing SQL Server installation media"
  type        = string
  default     = "dev-sqlserver-supportfiles-backups-and-iso-files"
}

variable "sql_iso_key" {
  description = "S3 key for SQL Server ISO file"
  type        = string
  default     = "media/SERVER_EVAL_x64FRE_en-us.iso"
}

variable "sql_cu_key" {
  description = "S3 key for SQL Server cumulative update"
  type        = string
  default     = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"
}

variable "enable_rds_custom" {
  description = "Enable RDS Custom SQL Server provisioning (requires custom AMI/CEV)"
  type        = bool
  default     = false
}

variable "rds_instance_class" {
  description = "RDS Custom instance class"
  type        = string
  default     = "db.m5.xlarge"
}

variable "rds_allocated_storage" {
  description = "Allocated storage for RDS Custom (GB)"
  type        = number
  default     = 100
}
