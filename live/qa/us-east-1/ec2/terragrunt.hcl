############################################################
# EC2 (t3.small by default via ec2.yaml)
#
# Reads: live/qa/config/global.yaml, us-east-1/region.yaml,
#        live/qa/config/us-east-1/ec2/ec2.yaml
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  config_dir    = dirname(find_in_parent_folders("config/global.yaml"))
  ec            = yamldecode(file("${local.config_dir}/${local.region}/ec2/ec2.yaml"))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/ec2"
}

inputs = {
  environment   = local.environment
  project       = local.project
  instance_type = local.ec.instance_type
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "ec2"
    },
    local.ec.tags,
  )
}
