# ── ElastiCache (Redis) ───────────────────────────────────────────────
# Replaces the in-cluster Redis pod. A managed single-node t3.micro gives
# persistence, automatic minor-version upgrades, and CloudWatch metrics
# without any pod management overhead.
#
# Single AZ (no automatic failover) — this is dev; the cost of a replica
# pair ($30+/mo extra) isn't justified here. If Redis goes down, rate-limit
# state is lost (non-critical) and in-flight Celery tasks drain from SQS on
# the next worker restart (safe by design).

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${local.name}-redis-subnet-group"
  }
}

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis"
  description = "ElastiCache Redis - only EKS nodes may connect"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-redis-sg"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${local.name}-redis"
  description          = "aGorA dev Redis — rate limiting, pub/sub, Celery broker"

  node_type            = "cache.t3.micro"
  num_cache_clusters   = 1
  engine               = "redis"
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  # auth_token requires transit_encryption_enabled — use token-based auth
  # so the REDIS_URL carries the password and no open access is possible
  # even from inside the cluster.
  auth_token = random_password.redis_auth.result

  automatic_failover_enabled = false
  multi_az_enabled           = false

  auto_minor_version_upgrade = true

  # 1-day snapshot window, kept for 3 days — cheap safety net for dev.
  snapshot_window          = "03:00-04:00"
  snapshot_retention_limit = 3

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis_slow.name
    destination_type = "cloudwatch-logs"
    log_format       = "text"
    log_type         = "slow-log"
  }

  tags = {
    Name = "${local.name}-redis"
  }
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_cloudwatch_log_group" "redis_slow" {
  name              = "/aws/elasticache/${local.name}/redis/slow-log"
  retention_in_days = var.log_retention_days
}
