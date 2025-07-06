output "service_name" {
  description = "Name of the PostgreSQL service"
  value       = kubernetes_service.postgresql.metadata[0].name
}

output "service_port" {
  description = "Port of the PostgreSQL service"
  value       = 5432
}

# Admin database outputs
output "database_name" {
  description = "PostgreSQL admin database name"
  value       = var.database_name
}

output "username" {
  description = "PostgreSQL admin username"
  value       = var.username
}

# SPIRE-specific database outputs
output "spire_database_name" {
  description = "SPIRE database name"
  value       = var.spire_database_name
}

output "spire_username" {
  description = "SPIRE database username"
  value       = var.spire_username
}

output "secret_name" {
  description = "Name of the PostgreSQL secret containing credentials"
  value       = kubernetes_secret.postgresql.metadata[0].name
}

# Connection strings
output "admin_connection_string" {
  description = "PostgreSQL admin connection string"
  value       = "postgresql://${var.username}:${var.password}@${kubernetes_service.postgresql.metadata[0].name}:5432/${var.database_name}"
  sensitive   = true
}

output "spire_connection_string" {
  description = "SPIRE PostgreSQL connection string (WARNING: Uses ephemeral storage - data will be lost on pod restart)"
  value       = "postgresql://${var.spire_username}:${var.spire_password}@${kubernetes_service.postgresql.metadata[0].name}:5432/${var.spire_database_name}"
  sensitive   = true
}

output "connection_string" {
  description = "SPIRE PostgreSQL connection string (for backward compatibility)"
  value       = "postgresql://${var.spire_username}:${var.spire_password}@${kubernetes_service.postgresql.metadata[0].name}:5432/${var.spire_database_name}"
  sensitive   = true
}

output "deployment_name" {
  description = "Name of the PostgreSQL deployment"
  value       = kubernetes_deployment.postgresql.metadata[0].name
}

output "storage_type" {
  description = "Type of storage used (ephemeral - data is not persistent)"
  value       = "emptyDir (ephemeral)"
}

output "init_script_configmap" {
  description = "Name of the ConfigMap containing the database initialization script"
  value       = kubernetes_config_map.postgresql_init.metadata[0].name
}