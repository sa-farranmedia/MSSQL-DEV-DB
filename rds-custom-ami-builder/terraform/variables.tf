variable "project_name" {
  description = "Project name"
  type        = string
  default     = "legacy-webapp"
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

variable "s3_media_bucket" {
  description = "S3 bucket containing SQL Server media"
  type        = string
}

variable "sql_iso_key" {
  description = "S3 key for SQL Server ISO"
  type        = string
}

variable "sql_cu_key" {
  description = "S3 key for SQL Server Cumulative Update"
  type        = string
}

variable "sa_password_ssm_path" {
  description = "SSM Parameter Store path for SA password"
  type        = string
  default     = "/dev/legacy-webapp/rds/sa-password"
}


