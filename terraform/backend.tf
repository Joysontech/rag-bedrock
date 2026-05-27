terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "joysontech-tf-state-e3ca4053" # replace with $TF_STATE_BUCKET
    key          = "rag-bedrock/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # native S3 state locking
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}