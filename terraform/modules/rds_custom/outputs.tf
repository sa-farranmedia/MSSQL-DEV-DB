# Uncomment these outputs after RDS instance is created

output "db_instance_id" {
  description = "RDS Custom instance ID"
  value       = aws_db_instance.rds_custom.id
}

output "endpoint" {
  description = "RDS Custom endpoint"
  value       = aws_db_instance.rds_custom.endpoint
}

output "address" {
  description = "RDS Custom address"
  value       = aws_db_instance.rds_custom.address
}
output "rds_sg_id" {
  description = "Security Group ID used by the RDS Custom instance"
  value       = aws_security_group.rds_custom.id
}


output "subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.rds_custom.name
}


