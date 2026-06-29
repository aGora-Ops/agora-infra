variable "environment" {
  description = "Deployment environment (dev|prod)"
  type        = string
}

variable "service_names" {
  description = "List of service keys to create secrets for (e.g. [\"api\", \"worker\"])"
  type        = list(string)
}

variable "secrets" {
  description = "Map of service_key => map of secret key/value pairs to store at stagecraft/{environment}/{service_key}"
  type        = map(map(string))
  sensitive   = true
}
