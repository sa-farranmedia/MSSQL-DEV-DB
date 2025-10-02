# S3 backend configuration
# Initialize with: terraform init -backend-config=envs/dev/backend.hcl
#
# Note: S3 Object Lock (WORM/retention) protects state files from deletion/modification.
# This is separate from Terraform state locking. For state locking during operations,
# consider adding DynamoDB table configuration here:
#
# dynamodb_table = "terraform-state-lock"
# encrypt        = true

terraform {
  backend "s3" {
    # Configured via backend.hcl:
    # bucket         = "dev-sqlserver-supportfiles-backups-and-iso-files"
    # key            = "tfstate/dev/infra.tfstate"
    # region         = "us-east-2"
  }
}
