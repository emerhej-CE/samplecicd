variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type = map(string)
}

variable "value_a" {
  type        = string
  default     = ""
  description = "SSM string value (empty allowed)."
}

variable "value_b" {
  type        = string
  default     = ""
  description = "SSM string value (empty allowed)."
}
