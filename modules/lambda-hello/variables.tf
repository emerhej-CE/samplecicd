variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to the Lambda function."
  default     = {}
}
