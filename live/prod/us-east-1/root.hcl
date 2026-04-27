# Regional root — same pattern as portal-mono live/prod/us-east-1/root.hcl
# For `terragrunt run --all plan` from this directory: set TG_PARALLELISM=1 (and AWS_PROFILE + TG_AWS_PROFILE
# to your local profile) so stacks do not queue on the same DynamoDB state lock.
locals {
  aws_region = "us-east-1"
  # Optional named profile for local runs only. Leave unset in CI so the AWS provider
  # uses the default chain (e.g. GitHub Actions OIDC). Example: export TG_AWS_PROFILE=tazakerV3
  aws_profile      = get_env("TG_AWS_PROFILE", "")
  backend_bucket   = get_env("TG_BACKEND_BUCKET", "tazakerv3-prod-terraform-state-use1")
  backend_dynamodb = get_env("TG_BACKEND_DYNAMODB", "tazakerv3-prod-terraform-use1-locks")
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
  region = "${local.aws_region}"${local.aws_profile == "" ? "" : "\n  profile = \"${local.aws_profile}\""}
}
EOF
}
