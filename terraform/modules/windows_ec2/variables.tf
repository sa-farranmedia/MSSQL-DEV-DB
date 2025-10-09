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

variable "subnet_id" {
  description = "Subnet ID for EC2 instance"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "s3_media_bucket" {
  description = "S3 bucket for media and backups"
  type        = string
}

variable "primary_private_ip" {
  description = "Primary private IP for EC2 instance"
  type        = string
}

variable "secondary_ips" {
  description = "List of secondary private IPs to assign"
  type        = list(string)
}

variable "ssm_allowed_users" {
  description = "List of IAM usernames allowed to start SSM sessions"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "rds_security_group_id" {
  description = "For RDS basion connection"
  type        = string
}

variable "key_name" {
  description = "EC2 Key Pair name for password decryption"
  type        = string
}
