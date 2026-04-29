resource "aws_ssm_parameter" "a" {
  name        = "/${var.project}/${var.environment}/ssm-params/param-a"
  description = "QA incremental-apply test parameter A"
  type        = "String"
  value       = var.value_a

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-ssm-param-a" })
}

resource "aws_ssm_parameter" "b" {
  name        = "/${var.project}/${var.environment}/ssm-params/param-b"
  description = "QA incremental-apply test parameter B"
  type        = "String"
  value       = var.value_b

  tags = merge(var.common_tags, { Name = "${var.project}-${var.environment}-ssm-param-b" })
}
