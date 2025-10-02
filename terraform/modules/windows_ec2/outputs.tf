output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.windows.id
}

output "instance_private_ip" {
  description = "Primary private IP"
  value       = aws_instance.windows.private_ip
}

output "primary_eni_id" {
  description = "Primary ENI ID"
  value       = aws_instance.windows.primary_network_interface_id
}

output "additional_eni_ids" {
  description = "Additional ENI IDs (if multi_eni strategy)"
  value       = local.use_multi_eni ? aws_network_interface.additional[*].id : []
}

output "static_private_ips" {
  description = "List of 5 static private IPs"
  value = local.use_secondary_ips ? (
    length(aws_network_interface.primary) > 0 ? aws_network_interface.primary[0].private_ips : []
    ) : (
    local.use_multi_eni ? flatten([
      for eni in aws_network_interface.additional : eni.private_ips
    ]) : []
  )
}

output "security_group_id" {
  description = "EC2 security group ID"
  value       = aws_security_group.ec2.id
}
