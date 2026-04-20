locals {
  identifier = "${var.project}-${var.environment}-pg"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "by_id" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

locals {
  # RDS subnet groups need subnets in at least two AZs; pick one subnet per AZ, then first two AZs (sorted).
  azs_sorted = sort(distinct([for s in data.aws_subnet.by_id : s.availability_zone]))
  subnet_per_az = {
    for az in local.azs_sorted :
    az => one([for id, s in data.aws_subnet.by_id : id if s.availability_zone == az])
  }
  db_subnet_ids = length(local.azs_sorted) >= 2 ? [
    local.subnet_per_az[local.azs_sorted[0]],
    local.subnet_per_az[local.azs_sorted[1]]
  ] : []
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.identifier}-subnets"
  subnet_ids = local.db_subnet_ids

  lifecycle {
    precondition {
      condition     = length(local.db_subnet_ids) == 2
      error_message = "Default VPC must have subnets in at least two availability zones for this RDS subnet group."
    }
  }

  tags = merge(var.common_tags, { Name = "${local.identifier}-subnets" })
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.identifier}-"
  vpc_id      = data.aws_vpc.default.id
  description = "PostgreSQL from VPC"

  ingress {
    description = "PostgreSQL within VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${local.identifier}-sg" })
}

resource "aws_db_instance" "this" {
  identifier = local.identifier

  engine                   = "postgres"
  engine_version           = var.engine_version
  instance_class           = var.instance_class
  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  db_subnet_group_name     = aws_db_subnet_group.this.name
  vpc_security_group_ids   = [aws_security_group.rds.id]
  publicly_accessible      = false
  multi_az                 = false

  db_name  = var.db_name
  username = var.master_username

  manage_master_user_password = true

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = merge(var.common_tags, { Name = local.identifier })
}
