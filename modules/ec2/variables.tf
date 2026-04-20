variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (e.g. t3.small)."
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
