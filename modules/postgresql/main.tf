resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "postgresql-secret"
    namespace = var.namespace
  }

  data = {
    username       = var.username
    password       = var.password
    spire_username = var.spire_username
    spire_password = var.spire_password
  }

  type = "Opaque"
}

resource "kubernetes_config_map" "postgresql" {
  metadata {
    name      = "postgresql-config"
    namespace = var.namespace
  }

  data = {
    POSTGRES_DB   = var.database_name
    POSTGRES_USER = var.username
    PGDATA        = "/var/lib/postgresql/data/pgdata"
  }
}

resource "kubernetes_config_map" "postgresql_init" {
  metadata {
    name      = "postgresql-init-script"
    namespace = var.namespace
  }

  data = {
    "init-spire.sh" = <<-EOT
      #!/bin/bash
      set -e

      echo "=== SPIRE Database Initialization Script Starting ==="
      echo "Timestamp: $(date)"
      echo "Current user: $(whoami)"
      echo "Target database: ${var.spire_database_name}"
      echo "Target username: ${var.spire_username}"

      # Function to execute SQL as postgres user
      execute_sql() {
        echo "Executing SQL: $1"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
          $1
      EOSQL
      }

      # Create SPIRE database
      echo "Creating database ${var.spire_database_name}..."
      execute_sql "SELECT 'CREATE DATABASE ${var.spire_database_name}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${var.spire_database_name}')\\gexec"

      # Create SPIRE user
      echo "Creating user ${var.spire_username}..."
      execute_sql "
        DO \$\$
        BEGIN
          IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${var.spire_username}') THEN
            CREATE ROLE ${var.spire_username} LOGIN PASSWORD '${var.spire_password}';
            RAISE NOTICE 'Created user: ${var.spire_username}';
          ELSE
            ALTER ROLE ${var.spire_username} PASSWORD '${var.spire_password}';
            RAISE NOTICE 'Updated password for existing user: ${var.spire_username}';
          END IF;
        END
        \$\$;
      "

      # Grant database privileges
      echo "Granting database privileges..."
      execute_sql "GRANT ALL PRIVILEGES ON DATABASE ${var.spire_database_name} TO ${var.spire_username};"

      # Connect to SPIRE database and set up schema privileges
      echo "Setting up schema privileges in ${var.spire_database_name}..."
      psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "${var.spire_database_name}" <<-EOSQL
        GRANT ALL ON SCHEMA public TO ${var.spire_username};
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${var.spire_username};
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${var.spire_username};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${var.spire_username};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${var.spire_username};

        -- Create extensions
        CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        CREATE EXTENSION IF NOT EXISTS "pgcrypto";
      EOSQL

      # Test connection
      echo "Testing SPIRE user connection..."
      PGPASSWORD='${var.spire_password}' psql -h localhost -U ${var.spire_username} -d ${var.spire_database_name} -c "SELECT current_user, current_database(), 'Connection successful!' as status;" || {
        echo "ERROR: Failed to connect as ${var.spire_username}"
        echo "Debugging user information:"
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "\\du ${var.spire_username};"
        exit 1
      }

      echo "=== SPIRE Database Initialization Completed Successfully ==="
      echo "Database: ${var.spire_database_name}"
      echo "Username: ${var.spire_username}"
      echo "Connection string: postgresql://${var.spire_username}:****@localhost:5432/${var.spire_database_name}"
    EOT
  }
}

resource "kubernetes_deployment" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
    labels = {
      app = "postgresql"
    }
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "postgresql"
      }
    }

    template {
      metadata {
        labels = {
          app = "postgresql"
        }
        annotations = {
          "init-script-hash" = sha256(kubernetes_config_map.postgresql_init.data["init-spire.sh"])
        }
      }

      spec {
        container {
          name  = "postgresql"
          image = "postgres:15-alpine"

          port {
            container_port = 5432
            name           = "postgresql"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.postgresql.metadata[0].name
            }
          }

          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.postgresql.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "POSTGRES_INITDB_ARGS"
            value = "--auth-host=scram-sha-256 --auth-local=scram-sha-256"
          }

          volume_mount {
            name       = "postgresql-data"
            mount_path = "/var/lib/postgresql/data"
          }

          volume_mount {
            name       = "postgresql-init-script"
            mount_path = "/docker-entrypoint-initdb.d"
            read_only  = true
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", var.username, "-d", var.database_name]
            }
            initial_delay_seconds = 120
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", var.username, "-d", var.database_name]
            }
            initial_delay_seconds = 60
            period_seconds        = 5
            timeout_seconds       = 1
            failure_threshold     = 3
          }

          startup_probe {
            exec {
              command = ["pg_isready", "-U", var.username, "-d", var.database_name]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 60
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "postgresql-data"
          empty_dir {
            size_limit = var.storage_size
          }
        }

        volume {
          name = "postgresql-init-script"
          config_map {
            name         = kubernetes_config_map.postgresql_init.metadata[0].name
            default_mode = "0755"
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }

        security_context {
          fs_group = 999
        }
      }
    }
  }
}

resource "kubernetes_service" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
    labels = {
      app = "postgresql"
    }
  }

  spec {
    selector = {
      app = "postgresql"
    }

    port {
      name        = "postgresql"
      port        = 5432
      target_port = 5432
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}