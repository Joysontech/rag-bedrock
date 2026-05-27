variable "project" {
  type        = string
  description = "Project name for tagging and naming"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy into"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the DB subnet group"
}

variable "aurora_security_group_id" {
  type        = string
  description = "Security group ID for Aurora (from networking module)"
}

variable "database_name" {
  type    = string
  default = "ragdb"
}

variable "master_username" {
  type    = string
  default = "rag_admin"
}

variable "engine_version" {
  type        = string
  default     = "16.4"
  description = "Aurora PostgreSQL engine version; pgvector available from 15.4+"
}

variable "min_capacity" {
  type        = number
  default     = 0
  description = "Min ACU. Set to 0 for scale-to-zero if region supports it."
}

variable "max_capacity" {
  type    = number
  default = 2
}

variable "backup_retention_days" {
  type    = number
  default = 1
}