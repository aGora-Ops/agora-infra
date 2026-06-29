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
  description          = "Stagecraft dev Redis - rate limiting, pub/sub, Celery broker"

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
  auth_token                 = random_password.redis_auth.result

  automatic_failover_enabled = false
  multi_az_enabled           = false

  auto_minor_version_upgrade = true

  snapshot_window          = "03:00-04:00"
  snapshot_retention_limit = 3

  tags = {
    Name = "${local.name}-redis"
  }
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}
