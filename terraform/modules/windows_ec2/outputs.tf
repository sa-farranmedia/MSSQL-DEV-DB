output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.windows.id
}

output "private_ip" {
  description = "Primary private IP"
  value       = aws_instance.windows.private_ip
}

output "all_private_ips" {
  description = "All private IPs (primary + secondary)"
  value       = concat([aws_instance.windows.private_ip], var.secondary_ips)
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.ec2.id
}

output "iam_role_arn" {
  description = "IAM role ARN"
  value       = aws_iam_role.ec2.arn
}


