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

module "lambda" {
  source = "./modules/lambda"

  project                  = var.project
  region                   = var.region
  vpc_id                   = module.networking.vpc_id
  subnet_ids               = module.networking.private_subnet_ids
  lambda_security_group_id = module.networking.lambda_security_group_id

  aurora_secret_arn    = module.database.master_user_secret_arn
  aurora_endpoint      = module.database.cluster_endpoint
  aurora_database_name = module.database.database_name
}
