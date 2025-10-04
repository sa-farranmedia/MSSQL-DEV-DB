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

output "ec2_instance_id" {
  description = "Windows EC2 instance ID"
  value       = module.windows_ec2.instance_id
}

output "ec2_private_ip" {
  description = "Windows EC2 primary private IP"
  value       = module.windows_ec2.private_ip
}

output "ec2_all_private_ips" {
  description = "All Windows EC2 private IPs (primary + secondary)"
  value       = module.windows_ec2.all_private_ips
}

output "rds_custom_endpoint" {
  description = "RDS Custom endpoint (if enabled)"
  value       = var.enable_rds_custom ? module.rds_custom[0].endpoint : "Not enabled"
}

output "rds_custom_instance_id" {
  description = "RDS Custom instance ID (if enabled)"
  value       = var.enable_rds_custom ? module.rds_custom[0].db_instance_id : "Not enabled"
}

output "ssm_start_session_command" {
  description = "Command to start SSM session to EC2"
  value       = "aws ssm start-session --target ${module.windows_ec2.instance_id}"
}

output "ssm_rdp_port_forward_command" {
  description = "Command to start RDP port forwarding"
  value       = "aws ssm start-session --target ${module.windows_ec2.instance_id} --document-name AWS-StartPortForwardingSession --parameters 'portNumber=3389,localPortNumber=13389'"
}

output "ssm_sql_port_forward_command" {
  description = "Command to start SQL Server port forwarding (if RDS enabled)"
  value       = var.enable_rds_custom ? "aws ssm start-session --target ${module.windows_ec2.instance_id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"${module.rds_custom[0].endpoint}\"],\"portNumber\":[\"1433\"],\"localPortNumber\":[\"11433\"]}'" : "RDS Custom not enabled"
}


