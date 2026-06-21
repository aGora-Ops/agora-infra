# ── Container Registry (ECR) ─────────────────────────────────────────
# One immutable-tag repo per service image.

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.2"

  for_each = toset(["agora-api", "agora-webhook", "agora-worker", "agora-frontend", "agora-mcp-aws", "agora-mcp-github"])

  repository_name                 = each.key
  repository_image_tag_mutability = "IMMUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
