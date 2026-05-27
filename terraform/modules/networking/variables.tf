variable "project" {
  type        = string
  description = "Project name for tagging and naming"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.42.0.0/16"
  description = "CIDR block for the VPC"
}

variable "azs" {
  type        = list(string)
  description = "Two AZs to deploy private subnets across"
  validation {
    condition     = length(var.azs) == 2
    error_message = "Provide exactly 2 availability zones."
  }
}