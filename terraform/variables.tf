variable "project_name" {
  description = "Project name (use 'legacy-webapp' only)"
  type        = string
  default     = "legacy-webapp"

  validation {
    condition     = var.project_name == "legacy-webapp"
    error_message = "Project name must be 'legacy-webapp' (not 'wepabb' or 'legacy-wepabb')."
  }
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.42.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (3 AZs)"
  type        = list(string)
  default     = ["10.42.0.0/20", "10.42.16.0/20", "10.42.32.0/20"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (2 AZs)"
  type        = list(string)
  default     = ["10.42.240.0/24", "10.42.241.0/24"]
}

variable "additional_ip_strategy" {
  description = "Strategy for additional private IPs (only 'secondary_ips' supported)"
  type        = string
  default     = "secondary_ips"

  validation {
    condition     = var.additional_ip_strategy == "secondary_ips"
    error_message = "Only 'secondary_ips' strategy is supported (not 'multi_eni')."
  }
}

variable "static_ips" {
  description = "List of 6 static private IPs (1 primary + 5 secondary)"
  type        = list(string)
  default = [
    "10.42.0.60", "10.42.0.61", "10.42.0.62",
    "10.42.0.63", "10.42.0.64", "10.42.0.65"
  ]

  validation {
    condition     = length(var.static_ips) == 6
    error_message = "Must provide exactly 6 static IPs (1 primary + 5 secondary)."
  }
}

variable "enable_rds_custom" {
  description = "Enable RDS Custom for SQL Server (set to true after CEV is registered)"
  type        = bool
  default     = false
}

variable "enable_scheduler" {
  description = "Enable RDS Custom start/stop scheduler"
  type        = bool
  default     = true
}

variable "ssm_allowed_iam_usernames" {
  description = "List of IAM usernames allowed to start SSM sessions"
  type        = list(string)
  default     = ["dev-brandon-leal"]
}

variable "s3_media_bucket" {
  description = "S3 bucket containing SQL Server media and backups"
  type        = string
  default     = "dev-sqlserver-supportfiles-backups-and-iso-files"
}

variable "sql_iso_key" {
  description = "S3 key for SQL Server ISO"
  type        = string
  default     = "media/SQLServer2022-x64-ENU-Dev.iso"
}

variable "sql_cu_key" {
  description = "S3 key for SQL Server Cumulative Update"
  type        = string
  default     = "media/sqlserver2022-kb5041321-x64_1b40129fb51df67f28feb2a1ea139044c611b93f.exe"
}

variable "rds_instance_class" {
  description = "RDS Custom instance class"
  type        = string
  default     = "db.m5.xlarge"
}

variable "rds_allocated_storage" {
  description = "RDS Custom allocated storage in GB"
  type        = number
  default     = 900
}


