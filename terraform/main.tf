# ---------------------
# VPC
# ---------------------
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  availability_zones   = local.azs
  # rds_sg_id = module.rds_custom.rds_sg_id
  tags = local.common_tags
}

# -----------------------------------------
# Windows EC2 AMI Builder (cleaned module)
# -----------------------------------------
module "windows_ec2" {
  source = "./modules/windows_ec2"

  project_name = var.project_name
  env          = var.env
  region       = var.region

  vpc_id            = module.vpc.vpc_id
  subnet_id         = module.vpc.private_subnet_ids[0]  # NOTE: swap to a public subnet if builder_public = true
  vpc_cidr          = var.vpc_cidr
  s3_media_bucket   = var.s3_media_bucket
  primary_private_ip = local.primary_ip
  secondary_ips     = local.secondary_ips
  ssm_allowed_users = var.ssm_allowed_iam_usernames

  # only create when feature flag is on (kept from your original intent)
  count = var.enable_rds_custom ? 1 : 0

  tags = local.common_tags
}

# -------------------------------------------------------
# RDS Custom (Web) – placeholder; uncomment when ready
# -------------------------------------------------------
module "rds_custom" {
  source = "./modules/rds_custom"

  dev_cev_version    = var.dev_cev_version
  project_name       = var.project_name
  env                = var.env
  region             = var.region
  vpce_security_group_id = module.vpc.vpce_security_group_id
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  vpc_cidr          = var.vpc_cidr
  instance_class     = var.rds_instance_class
  allocated_storage  = var.rds_allocated_storage
  enable_scheduler   = var.enable_scheduler
  db_master_username = var.custom_rds_username


  vpc = {
    ssm_vpce_id            = module.vpc.ssm_vpce_id
    ssmmessages_vpce_id    = module.vpc.ssmmessages_vpce_id
    ec2messages_vpce_id    = module.vpc.ec2messages_vpce_id
    logs_vpce_id           = module.vpc.logs_vpce_id
    events_vpce_id         = module.vpc.events_vpce_id
    monitoring_vpce_id     = module.vpc.monitoring_vpce_id
    secretsmanager_vpce_id = module.vpc.secretsmanager_vpce_id
    s3_gateway_vpce_id     = module.vpc.s3_gateway_vpce_id
  }
  depends_on = [module.vpc]
  tags = local.common_tags
  
}
