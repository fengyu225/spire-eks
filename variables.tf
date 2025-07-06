# =============================================================================
# VARIABLES.TF - Input Variables for SPIRE Infrastructure
# =============================================================================
# This file defines all input parameters for the Terraform configuration

# =============================================================================
# AWS CONFIGURATION
# =============================================================================
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in format like 'us-east-1' or 'eu-west-1'."
  }
}

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================
variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "spire"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name)) && length(var.project_name) <= 20
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and be max 20 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# =============================================================================
# NETWORK CONFIGURATION
# =============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for EKS."
  }
}

# =============================================================================
# EKS CONFIGURATION
# =============================================================================
variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"

  validation {
    condition     = can(regex("^1\\.(2[8-9]|3[0-2])$", var.kubernetes_version))
    error_message = "Kubernetes version must be between 1.28 and 1.32."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"

  validation {
    condition = contains([
      "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge", "m5.8xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge", "c5.9xlarge",
      "r5.large", "r5.xlarge", "r5.2xlarge", "r5.4xlarge"
    ], var.node_instance_type)
    error_message = "Instance type must be a valid EKS-supported instance type."
  }
}

variable "desired_capacity" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 10
    error_message = "Desired capacity must be between 1 and 10."
  }
}

variable "min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.min_size >= 1 && var.min_size <= 5
    error_message = "Minimum size must be between 1 and 5."
  }
}

variable "max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.max_size >= 2 && var.max_size <= 20
    error_message = "Maximum size must be between 2 and 20."
  }
}

# =============================================================================
# DEPLOYMENT CONTROL
# =============================================================================
variable "deploy_kubernetes_resources" {
  description = "Whether to deploy Kubernetes resources (PostgreSQL, SPIRE). Set to false for initial deployment."
  type        = bool
  default     = false
}

variable "enable_gitops" {
  description = "Enable GitOps deployment with ArgoCD/Flux"
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "Git repository URL for GitOps deployment"
  type        = string
  default     = ""
}

# =============================================================================
# SPIRE CONFIGURATION
# =============================================================================
variable "spire_trust_domain" {
  description = "SPIRE trust domain (e.g., example.org)"
  type        = string
  default     = "example.org"

  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.spire_trust_domain))
    error_message = "Trust domain must be a valid domain name (e.g., example.org)."
  }
}

variable "spire_server_image" {
  description = "SPIRE server container image"
  type        = string
  default     = "ghcr.io/spiffe/spire-server:1.11.2"
}

variable "spire_agent_image" {
  description = "SPIRE agent container image"
  type        = string
  default     = "ghcr.io/spiffe/spire-agent:1.11.2"
}

variable "controller_manager_image" {
  description = "SPIRE controller manager container image"
  type        = string
  default     = "ghcr.io/spiffe/spire-controller-manager:0.6.0"
}

variable "spire_log_level" {
  description = "Log level for SPIRE components"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR"], var.spire_log_level)
    error_message = "Log level must be one of: DEBUG, INFO, WARN, ERROR."
  }
}

variable "server_replicas" {
  description = "Number of SPIRE server replicas (for HA)"
  type        = number
  default     = 1

  validation {
    condition     = var.server_replicas >= 1 && var.server_replicas <= 5
    error_message = "Server replicas must be between 1 and 5."
  }
}

variable "enable_oidc_discovery" {
  description = "Enable OIDC discovery provider"
  type        = bool
  default     = true
}

variable "ca_ttl" {
  description = "Certificate Authority TTL (time to live)"
  type        = string
  default     = "48h"

  validation {
    condition     = can(regex("^[0-9]+[hm]$", var.ca_ttl))
    error_message = "CA TTL must be in format like '48h' or '30m'."
  }
}

variable "default_x509_svid_ttl" {
  description = "Default X.509 SVID TTL (time to live)"
  type        = string
  default     = "24h"

  validation {
    condition     = can(regex("^[0-9]+[hm]$", var.default_x509_svid_ttl))
    error_message = "X.509 SVID TTL must be in format like '24h' or '30m'."
  }
}

# =============================================================================
# POSTGRESQL CONFIGURATION
# =============================================================================
variable "spire_database_name" {
  description = "PostgreSQL database name for SPIRE"
  type        = string
  default     = "spiredb"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.spire_database_name))
    error_message = "Database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "spire_database_username" {
  description = "PostgreSQL username for SPIRE"
  type        = string
  default     = "spireuser"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.spire_database_username))
    error_message = "Database username must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "spire_database_password" {
  description = "PostgreSQL password for SPIRE (use a strong password in production)"
  type        = string
  default     = "password"
  sensitive   = true

  validation {
    condition     = length(var.spire_database_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "postgresql_storage_size" {
  description = "Storage size for PostgreSQL persistent volume"
  type        = string
  default     = "10Gi"

  validation {
    condition     = can(regex("^[0-9]+Gi$", var.postgresql_storage_size))
    error_message = "Storage size must be in format like '10Gi' or '20Gi'."
  }
}

variable "postgresql_storage_class" {
  description = "Storage class for PostgreSQL persistent volume"
  type        = string
  default     = "gp2"
}

variable "postgresql_backup_enabled" {
  description = "Enable automated PostgreSQL backups"
  type        = bool
  default     = false
}

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================
variable "enable_monitoring" {
  description = "Enable Prometheus monitoring for SPIRE"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enable centralized logging for SPIRE"
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================
variable "enable_pod_security_policies" {
  description = "Enable Pod Security Policies for enhanced security"
  type        = bool
  default     = true
}

variable "enable_network_policies" {
  description = "Enable Kubernetes Network Policies"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# =============================================================================
# BACKUP AND DISASTER RECOVERY
# =============================================================================
variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 30
    error_message = "Backup retention days must be between 1 and 30."
  }
}

variable "cross_region_backup" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = false
}

# =============================================================================
# TAGS
# =============================================================================
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9._:/=+@-]*$", k)) && can(regex("^[a-zA-Z0-9._:/=+@-]*$", v))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}

# =============================================================================
# FEATURE FLAGS
# =============================================================================
variable "enable_experimental_features" {
  description = "Enable experimental SPIRE features"
  type        = bool
  default     = false
}

variable "enable_federation" {
  description = "Enable SPIRE federation capabilities"
  type        = bool
  default     = false
}

variable "federation_domains" {
  description = "List of federated trust domains"
  type        = list(string)
  default     = []
}