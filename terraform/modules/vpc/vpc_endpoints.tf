locals {
  private_subnet_ids = aws_subnet.private[*].id  # or replace with your data source
  vpce_sg_id         = aws_security_group.vpc_endpoints.id
  vpc_id             = aws_vpc.main.id
  region             = data.aws_region.current.name
}
# locals in modules/vpc/*.tf
locals {
  private_route_table_ids = [aws_route_table.private.id]
}

# Secrets Manager
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, { Name = "${var.env}-${var.project_name}-vpce-secretsmanager" })
}

# EC2 (control-plane APIs RDS Custom touches)
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, { Name = "${var.env}-${var.project_name}-vpce-ec2" })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-ssm"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-ssmmessages"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-ec2messages"
  })
}
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-logs"
  })
}

resource "aws_vpc_endpoint" "events" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.events"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-events"
  })
}

resource "aws_vpc_endpoint" "monitoring" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-monitoring"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-vpce-s3"
  })
}


data "aws_route_tables" "private_rts" {
  vpc_id = local.vpc_id

  filter {
    name   = "association.subnet-id"
    values = local.private_subnet_ids
  }
}