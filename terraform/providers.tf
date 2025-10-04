provider "aws" {
  region = var.region

  default_tags {
    tags = {
      env     = var.env
      project = var.project_name
      managed = "terraform"
    }
  }
}


