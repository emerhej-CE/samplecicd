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
  default     = "placeholder"
  description = "SSM String value; AWS requires length >= 1."

  validation {
    condition     = length(var.value_a) >= 1
    error_message = "value_a must be non-empty (AWS SSM constraint)."
  }
}

variable "value_b" {
  type        = string
  default     = "placeholder"
  description = "SSM String value; AWS requires length >= 1."

  validation {
    condition     = length(var.value_b) >= 1
    error_message = "value_b must be non-empty (AWS SSM constraint)."
  }
}
