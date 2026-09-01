variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "name" {
  type    = string
  default = "bank-app-dev"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "db_admin_username" {
  type        = string
  description = "PostgreSQL administrator username."
  default     = "bankadmin"
}

variable "db_admin_password" {
  type        = string
  description = "PostgreSQL administrator password supplied through an ignored terraform.tfvars file."
  sensitive   = true

  validation {
    condition     = length(var.db_admin_password) >= 16
    error_message = "db_admin_password must contain at least 16 characters."
  }
}

variable "redis_auth_token" {
  type        = string
  description = "ElastiCache Redis auth token supplied through an ignored terraform.tfvars file."
  sensitive   = true

  validation {
    condition     = length(var.redis_auth_token) >= 16 && length(var.redis_auth_token) <= 128
    error_message = "redis_auth_token must contain between 16 and 128 characters."
  }
}
