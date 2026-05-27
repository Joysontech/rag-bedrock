output "vpc_id" {
  value = module.networking.vpc_id
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}

output "lambda_security_group_id" {
  value = module.networking.lambda_security_group_id
}

output "aurora_security_group_id" {
  value = module.networking.aurora_security_group_id
}

output "aurora_endpoint" {
  value = module.database.cluster_endpoint
}

output "aurora_secret_arn" {
  value = module.database.master_user_secret_arn
}

output "aurora_database_name" {
  value = module.database.database_name
}

output "ingest_function_name" {
  value = module.lambda.ingest_function_name
}

output "query_function_name" {
  value = module.lambda.query_function_name
}

output "docs_bucket" {
  value = module.lambda.docs_bucket
}

output "sessions_table" {
  value = module.lambda.sessions_table
}
