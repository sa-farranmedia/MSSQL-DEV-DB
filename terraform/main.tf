# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  env                  = var.env
  region               = var.region
  vpc_cidr             = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  azs                  = local.azs
}

# Windows EC2 Module
module "windows_ec2" {
  source = "./modules/windows_ec2"

  project_name           = var.project_name
  env                    = var.env
  region                 = var.region
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  additional_ip_strategy = var.additional_ip_strategy
  static_ips             = var.static_ips
  s3_media_bucket        = var.s3_media_bucket
}

# RDS Custom Module
module "rds_custom_dev" {
  source = "./modules/rds_custom_dev"

  project_name         = var.project_name
  env                  = var.env
  region               = var.region
  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = var.vpc_cidr
  private_subnet_ids   = module.vpc.private_subnet_ids
  enable_scheduler     = var.enable_scheduler
  enable_rds_custom    = var.enable_rds_custom
  rds_instance_class   = var.rds_instance_class
  rds_allocated_storage = var.rds_allocated_storage
}
