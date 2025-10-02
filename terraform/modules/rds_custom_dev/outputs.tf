output "rds_endpoint" {
  description = "RDS Custom endpoint (if enabled)"
  value       = var.enable_rds_custom ? "rds-custom-not-yet-provisioned" : null
  # Uncomment when DB instance is created:
  # value = var.enable_rds_custom ? aws_db_instance.rds_custom[0].endpoint : null
}

output "rds_arn" {
  description = "RDS Custom ARN (if enabled)"
  value       = var.enable_rds_custom ? "arn:aws:rds:${var.region}:account:db:${var.env}-${var.project_name}-sqlserver" : null
  # Uncomment when DB instance is created:
  # value = var.enable_rds_custom ? aws_db_instance.rds_custom[0].arn : null
}

output "scheduler_start_rule_arn" {
  description = "Start rule ARN"
  value       = var.enable_scheduler ? aws_cloudwatch_event_rule.start_weekdays[0].arn : null
}

output "scheduler_stop_rule_arn" {
  description = "Stop rule ARN"
  value       = var.enable_scheduler ? aws_cloudwatch_event_rule.stop_weeknights[0].arn : null
}

output "scheduler_lambda_arn" {
  description = "Scheduler Lambda ARN"
  value       = var.enable_scheduler ? aws_lambda_function.scheduler[0].arn : null
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds_custom.id
}

output "rds_subnet_group_name" {
  description = "RDS subnet group name"
  value       = aws_db_subnet_group.rds_custom.name
}
