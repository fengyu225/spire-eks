# AWS Configuration
aws_region = "us-east-1"

# Project Configuration
project_name = "spire"
environment  = "dev"

# Network Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

# EKS Configuration
kubernetes_version = "1.32"
node_instance_type = "t3.medium"
desired_capacity   = 2
min_size           = 1
max_size           = 3

# Deployment Configuration
deploy_kubernetes_resources = false

# SPIRE Configuration
spire_trust_domain = "example.org"

# PostgreSQL Configuration
spire_database_name     = "spire"
spire_database_username = "spire"
spire_database_password = "6oJOaHDbtXb2lxEha3Rwf7ymR"
postgresql_storage_size = "10Gi"
