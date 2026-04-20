output "endpoint" {
  description = "RDS hostname (no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS port."
  value       = aws_db_instance.this.port
}

output "identifier" {
  description = "DB instance identifier."
  value       = aws_db_instance.this.identifier
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN for the managed master password (when manage_master_user_password is true)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
