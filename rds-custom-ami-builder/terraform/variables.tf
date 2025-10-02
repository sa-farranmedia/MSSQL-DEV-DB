variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for AMI builder"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for AMI builder (private subnet recommended)"
  type        = string
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
  description = "S3 key for SQL Server cumulative update"
  type        = string
}

variable "sql_version" {
  description = "SQL Server version (2019 or 2022)"
  type        = string
  default     = "2022"
}

variable "sql_edition" {
  description = "SQL Server edition (Enterprise, Standard)"
  type        = string
  default     = "Enterprise"
}

variable "sql_instance_name" {
  description = "SQL Server instance name"
  type        = string
  default     = "MSSQLSERVER"
}

variable "sql_collation" {
  description = "SQL Server collation"
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
}

variable "builder_instance_type" {
  description = "EC2 instance type for AMI builder"
  type        = string
  default     = "m5.xlarge"
}

variable "builder_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 150
}
