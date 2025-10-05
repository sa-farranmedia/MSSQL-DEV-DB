variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for DB subnet group"
  type        = list(string)
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.m5.xlarge"
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 900
}

variable "enable_scheduler" {
  description = "Enable automated start/stop scheduler"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "db_master_username" {
  type        = string
  description = "Master username for RDS Custom SQL Server"
  default     = "sqladmin"
}

variable "db_master_password_param_name" {
  type        = string
  default     = "/dev/legacy-webapp/rds/master-password"
}

# # For secrets.tf
# variable "secret_name"              { type = string  default = "/dev/legacy-webapp/rds/master" }
#
# # DB connection details for the rotation function
# variable "db_host"                  { type = string }
# variable "db_port"                  { type = number  default = 1433 }
# variable "db_username"              { type = string }
# variable "db_instance_identifier"   { type = string } # e.g., "dev-legacy-webapp-rds-custom"
#
# # Lambda networking (rotation Lambda must reach your RDS in the VPC)
# variable "vpc_subnet_ids"           { type = list(string) } # private subnets that can reach DB
# variable "lambda_security_group_ids"{ type = list(string) } # SG with egress to DB:1433