# Regional root — same pattern as portal-mono tzkr/live/dev/us-east-1/root.hcl
locals {
  aws_region       = "us-east-1"
  aws_profile      = "tazakerV3"
  backend_bucket   = get_env("TG_BACKEND_BUCKET", "tazakerv3-dev-terraform-state-use1")
  backend_dynamodb = get_env("TG_BACKEND_DYNAMODB", "tazakerv3-dev-terraform-use1-locks")
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.backend_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = local.backend_dynamodb
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

terraform {
  extra_arguments "lock_timeout" {
    commands = [
      "apply",
      "destroy",
      "import",
      "plan",
      "refresh",
    ]
    arguments = [
      "-lock-timeout=15m",
    ]
  }
}

generate "terraform" {
  path      = "terraform.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.3.0"
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region  = "${local.aws_region}"
  profile = "${local.aws_profile}"
}
EOF
}
