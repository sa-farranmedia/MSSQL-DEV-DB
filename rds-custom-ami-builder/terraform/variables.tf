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

variable "base_ami_ssm_param" {
  description = "SSM Parameter Store path for the base Windows/SQL Server AMI"
  type        = string
  default     = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-SQL_2022_Developer"
}

variable "builder_public" {
  description = "If true, assign a public IP for the builder (uses Internet path for SSM)"
  type        = bool
  default     = true
}

variable "create_ssm_endpoints" {
  description = "Create Interface VPC Endpoints (ssm, ssmmessages, ec2messages) in the default VPC"
  type        = bool
  default     = false
}

variable "key_name" {
  type        = string
  description = "EC2 key pair name for Windows password decrypt"
}