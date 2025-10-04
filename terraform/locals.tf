locals {
  common_tags = {
    env     = var.env
    project = var.project_name
    managed = "terraform"
  }

  # Split static IPs: first is primary, rest are secondary
  primary_ip    = var.static_ips[0]
  secondary_ips = slice(var.static_ips, 1, length(var.static_ips))

  # Availability zones
  azs = data.aws_availability_zones.available.names
}

data "aws_availability_zones" "available" {
  state = "available"
}


