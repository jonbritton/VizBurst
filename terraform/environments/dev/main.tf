provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "domify"
      Environment = "dev"
      ManagedBy   = "opentofu"
    }
  }
}

module "networking" {
  source          = "../../modules/networking"
  name_prefix     = var.name_prefix
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

module "vpn" {
  source                 = "../../modules/vpn"
  name_prefix            = var.name_prefix
  vpc_id                 = module.networking.vpc_id
  studio_public_ip       = var.studio_public_ip
  onprem_cidrs           = var.onprem_cidrs
  private_route_table_id = module.networking.private_route_table_id
}

module "security" {
  source            = "../../modules/security"
  name_prefix       = var.name_prefix
  vpc_id            = module.networking.vpc_id
  vpc_cidr          = module.networking.vpc_cidr
  onprem_cidrs      = var.onprem_cidrs
  s3_prefix_list_id = module.networking.s3_prefix_list_id
}

module "storage" {
  source      = "../../modules/storage"
  name_prefix = var.name_prefix
}

module "fleet" {
  source            = "../../modules/fleet"
  name_prefix       = var.name_prefix
  workers_sg_id     = module.security.workers_sg_id
  assets_bucket_arn = module.storage.assets_bucket_arn
  frames_bucket_arn = module.storage.frames_bucket_arn
}

module "github_oidc" {
  source                = "../../modules/github-oidc"
  name_prefix           = var.name_prefix
  github_repo           = var.github_repo
  installers_bucket_arn = module.storage.installers_bucket_arn
}
