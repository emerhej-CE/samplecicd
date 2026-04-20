variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "bucket_suffix" {
  type        = string
  description = "Suffix in generated bucket name before random hex."
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
