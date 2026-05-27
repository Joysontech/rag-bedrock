output "cluster_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  value = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_port" {
  value = aws_rds_cluster.aurora.port
}

output "database_name" {
  value = aws_rds_cluster.aurora.database_name
}

output "master_user_secret_arn" {
  value = aws_rds_cluster.aurora.master_user_secret[0].secret_arn
}

output "cluster_arn" {
  value = aws_rds_cluster.aurora.arn
}