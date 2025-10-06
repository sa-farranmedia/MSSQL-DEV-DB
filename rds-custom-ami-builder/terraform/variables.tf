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
  description = "SSM public parameter for Windows Server 2019 Base AMI"
  type        = string
}

variable "filter" {
  description = "Windows Server 2019 Base AMI"
  type        = string
}

variable "builder_public" {
  description = "If true, assign a public IP for the builder (uses Internet path for SSM). If false, create SSM VPCEs and keep private."
  type        = bool
  default     = true
}

variable "create_ssm_endpoints" {
  description = "Create Interface VPC Endpoints (ssm, ssmmessages, ec2messages) in the default VPC for private SSM access. Ignored when builder_public = true unless explicitly set."
  type        = bool
  default     = false
}
variable "key_name" {
  type        = string
  description = "EC2 key pair name for Windows password decrypt"
}