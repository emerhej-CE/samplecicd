variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR for the VPC."
}

variable "az_count" {
  type        = number
  description = "Number of availability zones (public subnets, max 6)."
  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be between 1 and 6."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
