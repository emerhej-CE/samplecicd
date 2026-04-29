resource "aws_ssm_parameter" "a" {
  name        = "/${var.project}/${var.environment}/ssm-params/param-a"
  description = "Sample SSM parameter A (ssm-params stack)"
  type        = "String"
  value       = var.value_a

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-ssm-param-a" })
}

resource "aws_ssm_parameter" "b" {
  name        = "/${var.project}/${var.environment}/ssm-params/param-b"
  description = "Sample SSM parameter B (ssm-params stack)"
  type        = "String"
  value       = var.value_b

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-ssm-param-b" })
}
