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
#
# output "db_instance_id" {
#   description = "RDS Custom instance ID (placeholder until instance created)"
#   value       = "${var.env}-${var.project_name}-rds-custom"
# }
#
# output "endpoint" {
#   description = "RDS Custom endpoint (placeholder until instance created)"
#   value       = "CREATE RDS INSTANCE FIRST"
# }
#
# output "address" {
#   description = "RDS Custom address (placeholder until instance created)"
#   value       = "CREATE RDS INSTANCE FIRST"
# }

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds_custom.id
}

output "subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.rds_custom.name
}


