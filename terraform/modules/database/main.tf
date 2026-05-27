# ----------------------------------------------------------------------
# Subnet group
# ----------------------------------------------------------------------
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project}-aurora-subnets"
  subnet_ids = var.subnet_ids

  tags = { Name = "${var.project}-aurora-subnets" }
}

# ----------------------------------------------------------------------
# Cluster parameter group
# ----------------------------------------------------------------------
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project}-aurora-cluster-params"
  family      = "aurora-postgresql16"
  description = "${var.project} Aurora cluster parameters"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = { Name = "${var.project}-aurora-cluster-params" }
}

# ----------------------------------------------------------------------
# Aurora Serverless v2 cluster
# ----------------------------------------------------------------------
resource "aws_rds_cluster" "aurora" {
  cluster_identifier            = "${var.project}-cluster"
  engine                        = "aurora-postgresql"
  engine_mode                   = "provisioned"
  engine_version                = var.engine_version
  database_name                 = var.database_name
  master_username               = var.master_username

  enable_http_endpoint          = true

  manage_master_user_password   = true

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [var.aurora_security_group_id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name

  storage_encrypted = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:03:30-sun:04:30"

  skip_final_snapshot = true # learning project; flip to false for prod
  apply_immediately   = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
    seconds_until_auto_pause = 300
  }

  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = { Name = "${var.project}-cluster" }
}

# ----------------------------------------------------------------------
# Writer instance
# ----------------------------------------------------------------------
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.project}-writer"
  cluster_identifier = aws_rds_cluster.aurora.id
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  instance_class     = "db.serverless"

  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.aurora.arn

  tags = { Name = "${var.project}-writer" }
}