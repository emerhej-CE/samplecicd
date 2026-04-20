variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "s3_bucket_id" {
  type        = string
  description = "S3 bucket name (id) used as origin."
}

variable "s3_bucket_regional_domain_name" {
  type        = string
  description = "S3 bucket regional domain name for the CloudFront origin."
}

variable "enabled" {
  type        = bool
  description = "Whether the distribution is enabled."
  default     = true
}

variable "comment" {
  type        = string
  description = "Comment on the distribution."
}

variable "price_class" {
  type        = string
  description = "CloudFront price class."
  default     = "PriceClass_100"
}

variable "default_root_object" {
  type        = string
  description = "Default root object (e.g. index.html)."
  default     = "index.html"
}

variable "viewer_protocol_policy" {
  type        = string
  description = "Viewer protocol policy for default cache behavior."
  default     = "redirect-to-https"
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to the distribution."
  default     = {}
}
