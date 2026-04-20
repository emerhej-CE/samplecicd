variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_class" {
  type        = string
  description = "RDS instance class (e.g. db.t4g.micro for free-tier–eligible ARM)."
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage in GB (minimum 20 for gp3)."
  default     = 20
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL major.minor."
  default     = "16.4"
}

variable "db_name" {
  type        = string
  description = "Initial database name."
  default     = "appdb"
}

variable "master_username" {
  type        = string
  description = "Master username (not 'postgres' on newer PG — use e.g. appadmin)."
  default     = "appadmin"
}

variable "common_tags" {
  type        = map(string)
  default     = {}
  description = "Tags for RDS and related resources."
}
