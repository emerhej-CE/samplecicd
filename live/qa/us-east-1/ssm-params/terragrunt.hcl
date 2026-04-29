############################################################
# SSM Parameter Store (QA only) — two String params for incremental apply testing
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/ssm-params"
}

inputs = {
  environment = local.environment
  project     = local.project
  # AWS PutParameter rejects empty string; override in CI/locals if needed
  value_a = "placeholder"
  value_b = "placeholder"
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "ssm-params"
    },
  )
}
