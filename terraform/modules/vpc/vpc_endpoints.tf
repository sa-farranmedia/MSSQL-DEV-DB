
locals {
  private_subnet_ids = aws_subnet.private[*].id  # or replace with your data source
  vpce_sg_id         = aws_security_group.vpc_endpoints.id
  vpc_id             = aws_vpc.main.id
  region             = data.aws_region.current.name
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

# CloudWatch Monitoring (metrics)
resource "aws_vpc_endpoint" "monitoring" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.monitoring"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, { Name = "${var.env}-${var.project_name}-vpce-monitoring" })
}

# EventBridge / CloudWatch Events
resource "aws_vpc_endpoint" "events" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.events"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, { Name = "${var.env}-${var.project_name}-vpce-events" })
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

# EC2Messages (used by SSM agent)
resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${local.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [local.vpce_sg_id]
  private_dns_enabled = true
  tags = merge(var.tags, { Name = "${var.env}-${var.project_name}-vpce-ec2messages" })
}
# NOTE: You should already have these; keep them:
#   - ssm, ssmmessages, logs (Interface), and s3 (Gateway)
# If you later flip to Multi-AZ, also add: aws_vpc_endpoint.sqs (Interface).

# VPC Endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-logs-vpce"
  })
}

# VPC Endpoint for S3 (Gateway)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.private.id], [aws_route_table.public.id])

  tags = merge(var.tags, {
    Name = "${var.env}-${var.project_name}-s3-vpce"
  })
}
