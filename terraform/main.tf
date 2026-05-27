module "networking" {
  source  = "./modules/networking"
  project = var.project
  azs     = var.azs
}

module "database" {
  source = "./modules/database"

  project                  = var.project
  vpc_id                   = module.networking.vpc_id
  subnet_ids               = module.networking.private_subnet_ids
  aurora_security_group_id = module.networking.aurora_security_group_id
}