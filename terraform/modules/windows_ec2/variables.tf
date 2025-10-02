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
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs"
  type        = list(string)
}

variable "additional_ip_strategy" {
  description = "Strategy for additional IPs: secondary_ips or multi_eni"
  type        = string
}

variable "static_ips" {
  description = "List of 5 static private IPs"
  type        = list(string)
  default     = null
}

variable "s3_media_bucket" {
  description = "S3 bucket for SQL Server media"
  type        = string
}
