output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "instance_id" {
  description = "Windows EC2 instance ID"
  value       = module.windows_ec2.instance_id
}

output "instance_private_ip" {
  description = "Primary private IP of Windows EC2"
  value       = module.windows_ec2.instance_private_ip
}

output "primary_eni_id" {
  description = "Primary ENI ID"
  value       = module.windows_ec2.primary_eni_id
}

output "additional_eni_ids" {
  description = "Additional ENI IDs (if multi_eni strategy)"
  value       = module.windows_ec2.additional_eni_ids
}

output "static_private_ips" {
  description = "List of 5 static private IPs assigned"
  value       = module.windows_ec2.static_private_ips
}

output "ssm_connect_command" {
  description = "AWS CLI command to connect via SSM"
  value       = "aws ssm start-session --target ${module.windows_ec2.instance_id} --region ${var.region}"
}

output "rds_endpoint" {
  description = "RDS Custom endpoint (if enabled)"
  value       = module.rds_custom_dev.rds_endpoint
}

output "rds_arn" {
  description = "RDS Custom ARN (if enabled)"
  value       = module.rds_custom_dev.rds_arn
}

output "scheduler_start_rule_arn" {
  description = "EventBridge start rule ARN"
  value       = module.rds_custom_dev.scheduler_start_rule_arn
}

output "scheduler_stop_rule_arn" {
  description = "EventBridge stop rule ARN"
  value       = module.rds_custom_dev.scheduler_stop_rule_arn
}

output "scheduler_lambda_arn" {
  description = "Scheduler Lambda function ARN"
  value       = module.rds_custom_dev.scheduler_lambda_arn
}
