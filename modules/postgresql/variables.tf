variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "database_name" {
  description = "PostgreSQL default database name (admin database)"
  type        = string
  default     = "postgres"
}

variable "username" {
  description = "PostgreSQL admin username"
  type        = string
  default     = "postgres"
}

variable "password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

# SPIRE-specific Database Configuration
variable "spire_database_name" {
  description = "SPIRE-specific database name"
  type        = string
  default     = "spiredb"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.spire_database_name))
    error_message = "SPIRE database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "spire_username" {
  description = "SPIRE-specific database username"
  type        = string
  default     = "spireuser"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.spire_username))
    error_message = "SPIRE username must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "spire_password" {
  description = "SPIRE-specific database user password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.spire_password) >= 8
    error_message = "SPIRE database password must be at least 8 characters long."
  }
}

variable "storage_size" {
  description = "Storage size limit for PostgreSQL emptyDir volume (ephemeral storage - data will be lost on pod restart)"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+[GMK]i?$", var.storage_size))
    error_message = "Storage size must be in format like '10Gi', '512Mi', or '1G'."
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}