terraform {
  backend "s3" {
    # Configuration loaded from envs/dev/backend.hcl
    # Use: terraform init -backend-config=envs/dev/backend.hcl
  }
}


