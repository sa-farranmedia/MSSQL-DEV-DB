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

output "vpc_endpoint_ssm_id" {
  description = "SSM VPC Endpoint ID"
  value       = aws_vpc_endpoint.ssm.id
}

output "vpc_endpoint_ssmmessages_id" {
  description = "SSM Messages VPC Endpoint ID"
  value       = aws_vpc_endpoint.ssmmessages.id
}

output "vpc_endpoint_ec2messages_id" {
  description = "EC2 Messages VPC Endpoint ID"
  value       = aws_vpc_endpoint.ec2messages.id
}

output "vpc_endpoint_logs_id" {
  description = "CloudWatch Logs VPC Endpoint ID"
  value       = aws_vpc_endpoint.logs.id
}

output "vpc_endpoint_s3_id" {
  description = "S3 VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}


