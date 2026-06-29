# ── Database (RDS PostgreSQL) ────────────────────────────────────────
# db.t3.micro (SCP guardrail). Prod keeps a final snapshot and 7-day backups.

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "aws_db_instance" "postgres" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  db_name  = "stagecraft"
  username = "stagecraft"
  password = random_password.db_password.result

  allocated_storage = 20
  storage_type      = "gp2"

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.eks.node_security_group_id]

  skip_final_snapshot        = false
  final_snapshot_identifier  = "${local.name}-postgres-final"
  backup_retention_period    = 7
  auto_minor_version_upgrade = true
  publicly_accessible        = false
}
