provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "rag-bedrock"
      ManagedBy = "terraform"
      Owner     = "joyson"
      Repo      = "github.com/joysontech/rag-bedrock"
    }
  }
}