############################################################
# Lambda hello (prints hello world, returns body)
#
# Reads: live/qa/config/global.yaml, us-east-1/region.yaml,
#        live/qa/config/us-east-1/lambda-hello/lambda-hello.yaml
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  config_dir    = dirname(find_in_parent_folders("config/global.yaml"))
  lh            = yamldecode(file("${local.config_dir}/${local.region}/lambda-hello/lambda-hello.yaml"))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/lambda-hello"
}

inputs = {
  environment = local.environment
  project     = local.project
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "lambda-hello"
    },
    local.lh.tags,
  )
}
