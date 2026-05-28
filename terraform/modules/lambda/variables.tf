variable "project" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "lambda_security_group_id" {
  type = string
}

variable "aurora_secret_arn" {
  type        = string
  description = "Secrets Manager ARN for Aurora master password"
}

variable "aurora_endpoint" {
  type = string
}

variable "aurora_database_name" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "lambda_runtime" {
  type    = string
  default = "python3.12"
}

variable "lambda_memory" {
  type    = number
  default = 1024
}

variable "lambda_timeout" {
  type        = number
  default     = 300
  description = "Timeout in seconds. 300s covers Aurora scale-to-zero wake-up + embedding calls."
}
