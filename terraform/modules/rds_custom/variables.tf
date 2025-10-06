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

variable "vpc" {
  description = "VPC context required by RDS Custom"
  type = object({
    ssm_vpce_id            = string
    ssmmessages_vpce_id    = string
    ec2messages_vpce_id    = string
    logs_vpce_id           = string
    events_vpce_id         = string
    monitoring_vpce_id     = string
    secretsmanager_vpce_id = string
    s3_gateway_vpce_id     = string
  })
}