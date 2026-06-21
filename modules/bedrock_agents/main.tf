resource "aws_iam_role" "agent" {
  for_each = var.agents
  name = "${var.cluster_name}-bedrock-agent-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnLike       = { "aws:SourceArn" = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:agent/*" }
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

  agent_name              = "${var.cluster_name}-${each.key}"
  agent_resource_role_arn = aws_iam_role.agent[each.key].arn
  foundation_model        = each.value.foundation_model
  instruction             = each.value.instruction
  idle_session_ttl_in_seconds = 300

  tags = {
    Project     = "agora"
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
    aws_bedrockagent_agent_action_group.aws_diagnostics,
  ]
}

# Return-of-Control action group: agora-mcp-github READ-ONLY tools.
# Bedrock streams a returnControl event instead of executing anything; the
# worker (in-cluster, next to the MCP servers) calls the real MCP tool and
# re-invokes the agent with the result. No Lambda involved.
#
# Deliberately read-only: branch creation, commits, and PR opens stay outside
# agent reach. They only happen via the api-service "Raise PR" endpoint after
# a human reviews the suggestion — this keeps the prompt-injection blast
# radius limited to a bad suggestion the user can reject, not an autonomous
# write to the user's repository.
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

# Return-of-Control action group: agora-mcp-aws read-only diagnostics.
resource "aws_bedrockagent_agent_action_group" "aws_diagnostics" {
  for_each = toset([for k in ["root_cause"] : k if contains(keys(var.agents), k)])

  action_group_name = "aws-diagnostics"
  agent_id          = aws_bedrockagent_agent.this[each.key].agent_id
  agent_version     = "DRAFT"

  action_group_executor {
    custom_control = "RETURN_CONTROL"
  }

  function_schema {
    member_functions {
      functions {
        name        = "get_cloudwatch_logs"
        description = "Fetch the most recent log events from a CloudWatch Logs stream (read-only)."
        parameters {
          map_block_key = "log_group"
          type          = "string"
          description   = "CloudWatch log group, must start with /agora/ or /aws/containerinsights/"
          required      = true
        }
        parameters {
          map_block_key = "log_stream"
          type          = "string"
          description   = "CloudWatch log stream name"
          required      = true
        }
        parameters {
          map_block_key = "limit"
          type          = "integer"
          description   = "Maximum number of events to return (max 500)"
          required      = false
        }
      }

      functions {
        name        = "get_sqs_queue_depth"
        description = "Return approximate message counts for an SQS queue (read-only)."
        parameters {
          map_block_key = "queue_url"
          type          = "string"
          description   = "SQS queue URL, must contain 'agora'"
          required      = true
        }
      }

      functions {
        name        = "describe_ecr_image"
        description = "Return metadata for an ECR image (read-only)."
        parameters {
          map_block_key = "repository_name"
          type          = "string"
          description   = "ECR repository name, must start with 'agora-'"
          required      = true
        }
        parameters {
          map_block_key = "image_tag"
          type          = "string"
          description   = "Image tag to describe"
          required      = true
        }
      }
    }
  }
}
