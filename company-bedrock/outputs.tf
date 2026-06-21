output "agent_ids" {
  description = "Map of agent_key => Bedrock agent ID. Copy into agora/<env>/worker Secrets Manager."
  value       = module.bedrock_agents.agent_ids
}

output "agent_alias_ids" {
  description = "Map of agent_key => Bedrock agent alias ID. Copy into agora/<env>/worker Secrets Manager."
  value       = module.bedrock_agents.agent_alias_ids
}
