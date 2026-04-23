############################################################
# CloudFront (S3 origin + OAC)
#
# Reads: live/qa/config/global.yaml, us-east-1/region.yaml,
#        live/qa/config/us-east-1/cloudfront/cloudfront.yaml
# Depends: ../s3 (apply S3 before this stack)
############################################################

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region        = yamldecode(file(find_in_parent_folders("region.yaml"))).region
  global_config = yamldecode(file(find_in_parent_folders("config/global.yaml")))
  config_dir    = dirname(find_in_parent_folders("config/global.yaml"))
  cf            = yamldecode(file("${local.config_dir}/${local.region}/cloudfront/cloudfront.yaml"))
  environment   = local.global_config.global.environment
  project       = local.global_config.global.project
}

terraform {
  source = "../../../../modules/cloudfront"
}

dependency "s3" {
  config_path = "../s3"

  mock_outputs = {
    bucket_id                   = "mock-bucket-placeholder"
    bucket_regional_domain_name = "mock-bucket-placeholder.s3.us-east-1.amazonaws.com"
  }
}

inputs = {
  environment                    = local.environment
  project                        = local.project
  enabled                        = local.cf.enabled
  comment                        = local.cf.comment
  price_class                    = local.cf.price_class
  default_root_object            = local.cf.default_root_object
  viewer_protocol_policy         = local.cf.viewer_protocol_policy
  s3_bucket_id                   = dependency.s3.outputs.bucket_id
  s3_bucket_regional_domain_name = dependency.s3.outputs.bucket_regional_domain_name
  common_tags = merge(
    local.global_config.global,
    local.global_config.global_tags,
    {
      Region    = local.region
      Component = "cloudfront"
    },
    local.cf.tags,
  )
}
