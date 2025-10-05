project_name = "legacy-webapp"
env          = "dev"
region       = "us-east-2"

# ami-05f848027a4b5cd25
li_ami_ssm_param = "/aws/service/ami-windows-latest/Windows_Server-2019-English-Full-SQL_2022_Web"

# being built public does not stop you from becoming an RDS custom instance on a private VPC
builder_public       = true
create_ssm_endpoints = false