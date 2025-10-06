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

output "rds_custom_endpoint" {
  description = "RDS Custom endpoint (if enabled)"
  value       = var.enable_rds_custom ? module.rds_custom.endpoint : "Not enabled"
}

output "rds_custom_instance_id" {
  description = "RDS Custom instance ID (if enabled)"
  value       = var.enable_rds_custom ? module.rds_custom.db_instance_id : "Not enabled"
}

output "ssm_sql_port_forward_command" {
  description = "Command to start SQL Server port forwarding (if RDS enabled)"
  value       = var.enable_rds_custom ? "aws ssm start-session --target ${module.windows_ec2[0].instance_id} --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters '{\"host\":[\"${module.rds_custom.endpoint}\"],\"portNumber\":[\"1433\"],\"localPortNumber\":[\"11433\"]}'" : "RDS Custom not enabled"
}

# If module.windows_ec2 has count=0, these safely return null/[].

output "ec2_instance_id" {
  description = "Windows builder instance id"
  value       = try(module.windows_ec2[0].instance_id, null)
}

output "ec2_private_ip" {
  description = "Windows builder primary private IP"
  value       = try(module.windows_ec2[0].private_ip, null)
}

output "ec2_all_private_ips" {
  description = "All private IPs on the builder ENI(s)"
  value       = try(module.windows_ec2[0].all_private_ips, [])
}

output "ssm_start_session_command" {
  description = "Command to start SSM session to the builder"
  value       = try(format("aws ssm start-session --target %s", module.windows_ec2[0].instance_id), null)
}

output "ssm_rdp_port_forward_command" {
  description = "SSM port forward for RDP 3389 -> 13389"
  value       = try(format("aws ssm start-session --target %s --document-name AWS-StartPortForwardingSession --parameters 'portNumber=3389,localPortNumber=13389'", module.windows_ec2[0].instance_id), null)
}