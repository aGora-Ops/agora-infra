resource "aws_iam_role" "agent" {
  for_each = var.agents
  name     = "${var.cluster_name}-bedrock-agent-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:agent/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "agent_model" {
  for_each = var.agents
  name     = "invoke-model"
  role     = aws_iam_role.agent[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel"]
      Resource = each.value.model_arn
    }]
  })
}

resource "aws_bedrockagent_agent" "this" {
  for_each = var.agents

  agent_name                  = "${var.cluster_name}-${each.key}"
  agent_resource_role_arn     = aws_iam_role.agent[each.key].arn
  foundation_model            = each.value.foundation_model
  instruction                 = each.value.instruction
  idle_session_ttl_in_seconds = 300

  tags = {
    Project     = "stagecraft"
    Environment = var.environment
    AgentRole   = each.key
  }
}

resource "aws_bedrockagent_agent_alias" "this" {
  for_each = var.agents

  agent_id         = aws_bedrockagent_agent.this[each.key].agent_id
  agent_alias_name = "live"

  depends_on = [
    aws_bedrockagent_agent_action_group.github_tools,
  ]
}

resource "aws_bedrockagent_agent_action_group" "github_tools" {
  for_each = toset([for k in ["root_cause", "yaml_fixer"] : k if contains(keys(var.agents), k)])

  action_group_name = "github-tools"
  agent_id          = aws_bedrockagent_agent.this[each.key].agent_id
  agent_version     = "DRAFT"

  action_group_executor {
    custom_control = "RETURN_CONTROL"
  }

  function_schema {
    member_functions {
      functions {
        name        = "get_workflow_yaml"
        description = "Fetch a GitHub Actions workflow YAML file from a repository."
        parameters {
          map_block_key = "owner"
          type          = "string"
          description   = "Repository owner/org"
          required      = true
        }
        parameters {
          map_block_key = "repo"
          type          = "string"
          description   = "Repository name"
          required      = true
        }
        parameters {
          map_block_key = "path"
          type          = "string"
          description   = "Path to the workflow file, e.g. .github/workflows/ci.yml"
          required      = true
        }
        parameters {
          map_block_key = "ref"
          type          = "string"
          description   = "Git ref (branch, tag, or commit SHA)"
          required      = true
        }
      }

      functions {
        name        = "get_run_logs"
        description = "Download and return the last 300 lines of logs for a workflow run."
        parameters {
          map_block_key = "owner"
          type          = "string"
          description   = "Repository owner/org"
          required      = true
        }
        parameters {
          map_block_key = "repo"
          type          = "string"
          description   = "Repository name"
          required      = true
        }
        parameters {
          map_block_key = "run_id"
          type          = "integer"
          description   = "Workflow run ID"
          required      = true
        }
      }

    }
  }
}
