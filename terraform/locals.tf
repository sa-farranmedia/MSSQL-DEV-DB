locals {
  name_prefix = "${var.env}-${var.project_name}"

  common_tags = {
    Name    = "${local.name_prefix}"
    env     = var.env
    project = var.project_name
  }

  # SQL Server media references
  sql_iso_path = "s3://${var.s3_media_bucket}/${var.sql_iso_key}"
  sql_cu_path  = "s3://${var.s3_media_bucket}/${var.sql_cu_key}"

  # AZ mapping
  azs = data.aws_availability_zones.available.names
}

data "aws_availability_zones" "available" {
  state = "available"
}
