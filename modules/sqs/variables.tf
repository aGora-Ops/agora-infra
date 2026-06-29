variable "name" {
  description = "SQS queue name"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "max_receive_count" {
  description = "Max receive count before moving to DLQ"
  type        = number
  default     = 3
}

variable "sender_role_arn" {
  description = "IAM role ARN allowed to send messages (webhook service)"
  type        = string
}

variable "consumer_role_arn" {
  description = "IAM role ARN allowed to consume messages (worker)"
  type        = string
}

