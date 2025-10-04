# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  availability_zones   = local.azs

  tags = local.common_tags
}

# Windows EC2 Module
module "windows_ec2" {
  source = "./modules/windows_ec2"

  project_name = var.project_name
  env          = var.env
  region       = var.region

  vpc_id              = module.vpc.vpc_id
  subnet_id           = module.vpc.private_subnet_ids[0]
  vpc_cidr            = var.vpc_cidr
  s3_media_bucket     = var.s3_media_bucket
  primary_private_ip  = local.primary_ip
  secondary_ips       = local.secondary_ips
  ssm_allowed_users   = var.ssm_allowed_iam_usernames

  tags = local.common_tags
}

# RDS Custom Module (conditional)
module "rds_custom" {
  source = "./modules/rds_custom_dev"
  count  = var.enable_rds_custom ? 1 : 0

  project_name = var.project_name
  env          = var.env
  region       = var.region

  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  private_subnet_ids    = module.vpc.private_subnet_ids
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
  enable_scheduler      = var.enable_scheduler

  tags = local.common_tags
}


