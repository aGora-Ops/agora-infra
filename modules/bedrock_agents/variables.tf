variable "cluster_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "account_id" { type = string }

variable "agents" {
  description = "Map of agent_key => agent configuration"
  type = map(object({
    foundation_model = string
    model_arn        = string
    instruction      = string
  }))
}
