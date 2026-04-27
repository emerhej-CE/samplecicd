############################################################
# S3 bucket
#
# Reads: live/prod/config/global.yaml, us-east-1/region.yaml,
#        live/prod/config/us-east-1/s3/s3.yaml
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  config_dir    = dirname(find_in_parent_folders("config/global.yaml"))
  st            = yamldecode(file("${local.config_dir}/${local.region}/s3/s3.yaml"))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/s3"
}

inputs = {
  environment    = local.environment
  project        = local.project
  bucket_suffix  = local.st.bucket_suffix
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "s3"
    },
    local.st.tags,
  )
}
