locals {
  nova_pro_arn   = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0"
  nova_lite_arn  = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-lite-v1:0"
  nova_micro_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-micro-v1:0"
}

module "bedrock_agents" {
  source = "../modules/bedrock_agents"

  cluster_name = var.cluster_name
  environment  = var.environment
  aws_region   = var.aws_region
  account_id   = var.account_id

  agents = {
    classifier = {
      foundation_model = "amazon.nova-micro-v1:0"
      model_arn        = local.nova_micro_arn
      instruction      = "You classify GitHub Actions failure logs into one of a fixed set of categories. Respond with exactly one category name, nothing else."
    }
    root_cause = {
      foundation_model = "amazon.nova-pro-v1:0"
      model_arn        = local.nova_pro_arn
      instruction      = <<-EOT
        You analyse GitHub Actions failures to find the specific root cause.
        Use the github-tools action group (read-only: get_workflow_yaml, get_run_logs) and the
        aws-diagnostics action group (read-only: CloudWatch logs, SQS queue depth, ECR image
        metadata) when the failure looks infrastructure-related. You never write to GitHub or
        AWS — only read. Respond with a JSON object:
        {"root_cause": "...", "severity": "low|medium|high|critical"}.
      EOT
    }
    yaml_fixer = {
      foundation_model = "amazon.nova-pro-v1:0"
      model_arn        = local.nova_pro_arn
      instruction      = <<-EOT
        You produce a corrected GitHub Actions workflow YAML for a known root cause.
        Use the github-tools action group (read-only: get_workflow_yaml, get_run_logs) to fetch
        the current workflow YAML or extra log context if you need it. You never create
        branches, commit, or open pull requests — that happens outside your control after a
        human reviews your suggestion. Return only the complete, corrected YAML — no prose, no
        markdown fences.
      EOT
    }
    security_reviewer = {
      foundation_model = "amazon.nova-pro-v1:0"
      model_arn        = local.nova_pro_arn
      instruction      = "You review a proposed workflow YAML fix for security issues: hardcoded secrets, missing SHA pins, overbroad permissions, dangerous shell commands, untrusted registries. Respond with JSON: {\"risk_score\": 0-10, \"findings\": [...]}."
    }
    pr_writer = {
      foundation_model = "amazon.nova-lite-v1:0"
      model_arn        = local.nova_lite_arn
      instruction      = <<-EOT
        You write the pull request title and body for an AI-suggested workflow fix, given the
        root cause, failure category, and security findings. You have no tools and never touch
        GitHub directly — the actual branch, commit, and PR are created by the api-service only
        after a human reviews and approves your suggestion. Respond with JSON:
        {"title": "fix: ...", "body": "## Root Cause\n..."}.
      EOT
    }
  }
}
