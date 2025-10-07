output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "ssm_vpce_id"            { value = aws_vpc_endpoint.ssm.id }
output "ssmmessages_vpce_id"    { value = aws_vpc_endpoint.ssmmessages.id }
output "ec2messages_vpce_id"    { value = aws_vpc_endpoint.ec2messages.id }
output "logs_vpce_id"           { value = aws_vpc_endpoint.logs.id }
output "events_vpce_id"         { value = aws_vpc_endpoint.events.id }
output "monitoring_vpce_id"     { value = aws_vpc_endpoint.monitoring.id }
output "secretsmanager_vpce_id" { value = aws_vpc_endpoint.secretsmanager.id }
output "s3_gateway_vpce_id" { value = aws_vpc_endpoint.s3_gateway.id }

output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}

output "vpce_security_group_id" {
  description = "VPC Endpoints Security Group ID"
  value       = aws_security_group.vpc_endpoints.id
}
