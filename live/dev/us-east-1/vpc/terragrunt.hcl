############################################################
# VPC (dev only) — public subnets + Internet Gateway
#
# Reads: live/dev/config/global.yaml, us-east-1/region.yaml,
#        live/dev/config/us-east-1/vpc/vpc.yaml
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  config_dir    = dirname(find_in_parent_folders("config/global.yaml"))
  st            = yamldecode(file("${local.config_dir}/${local.region}/vpc/vpc.yaml"))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/vpc"
}

inputs = {
  environment = local.environment
  project     = local.project
  vpc_cidr    = local.st.vpc_cidr
  az_count    = local.st.az_count
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "vpc"
    },
    local.st.tags,
  )
}
