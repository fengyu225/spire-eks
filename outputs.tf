# Cluster Outputs
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

# Network Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

# Node Group Outputs
output "node_security_group_id" {
  description = "Security group ID attached to the EKS nodes"
  value       = module.eks.node_security_group_id
}

# SPIRE Outputs
output "spire_server_role_arn" {
  description = "ARN of the SPIRE server IAM role"
  value       = aws_iam_role.spire_server.arn
}

output "spire_bundle_s3_bucket" {
  description = "S3 bucket name for SPIRE bundle storage"
  value       = aws_s3_bucket.spire_bundle.bucket
}

output "spire_bundle_s3_bucket_url" {
  description = "S3 bucket URL for SPIRE bundle storage"
  value       = "https://${aws_s3_bucket.spire_bundle.bucket}.s3.amazonaws.com"
}

output "spire_trust_domain" {
  description = "SPIRE trust domain"
  value       = var.spire_trust_domain
}

# PostgreSQL Outputs
output "postgresql_service_name" {
  description = "PostgreSQL service name for SPIRE database"
  value       = var.deploy_kubernetes_resources ? module.postgresql[0].service_name : null
}

output "postgresql_connection_string" {
  description = "PostgreSQL connection string for SPIRE"
  value       = var.deploy_kubernetes_resources ? "postgresql://${var.spire_database_username}:${var.spire_database_password}@${module.postgresql[0].service_name}:5432/${var.spire_database_name}" : null
  sensitive   = true
}

# SSH Key Output
output "private_key_pem" {
  description = "Private key for SSH access to instances"
  value       = tls_private_key.main.private_key_pem
  sensitive   = true
}

# EBS CSI Driver Outputs
output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = module.ebs_csi_irsa_role.iam_role_arn
}

# Account Information
output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Deployment Information
output "deployment_info" {
  description = "Information about the SPIRE deployment"
  value = {
    cluster_name                  = local.cluster_name
    trust_domain                  = var.spire_trust_domain
    kubernetes_resources_deployed = var.deploy_kubernetes_resources
    spire_namespace               = var.deploy_kubernetes_resources ? kubernetes_namespace.spire[0].metadata[0].name : null
    s3_bundle_bucket              = aws_s3_bucket.spire_bundle.bucket
  }
}