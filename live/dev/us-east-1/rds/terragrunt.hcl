############################################################
# RDS PostgreSQL (default VPC, managed master password in Secrets Manager)
#
# Reads: live/dev/config/global.yaml, us-east-1/region.yaml,
#        live/dev/config/us-east-1/rds/rds.yaml
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  config_dir    = dirname(find_in_parent_folders("config/global.yaml"))
  rds_cfg       = yamldecode(file("${local.config_dir}/${local.region}/rds/rds.yaml"))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/rds"
}

inputs = {
  environment         = local.environment
  project             = local.project
  instance_class      = local.rds_cfg.instance_class
  allocated_storage   = local.rds_cfg.allocated_storage
  engine_version      = local.rds_cfg.engine_version
  db_name             = local.rds_cfg.db_name
  master_username     = local.rds_cfg.master_username
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "rds"
    },
    local.rds_cfg.tags,
  )
}
