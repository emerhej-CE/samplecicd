output "instance_id" {
  value       = aws_instance.this.id
  description = "EC2 instance ID."
}

output "public_ip" {
  value       = aws_instance.this.public_ip
  description = "Public IP when the subnet routes a public address."
}
