output "api_role_arn" { value = module.api_role.iam_role_arn }
output "api_role_name" { value = module.api_role.iam_role_name }

output "webhook_role_arn" { value = module.webhook_role.iam_role_arn }
output "webhook_role_name" { value = module.webhook_role.iam_role_name }

output "worker_role_arn" { value = module.worker_role.iam_role_arn }
output "worker_role_name" { value = module.worker_role.iam_role_name }

output "external_secrets_role_arn" { value = module.external_secrets_role.iam_role_arn }
