#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="spire"
DEPLOYMENT="postgresql"
SPIRE_DB="spiredb"
SPIRE_USER="spireuser"
SPIRE_PASSWORD="password"
POSTGRES_USER="postgres"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    echo "PostgreSQL SPIRE Setup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --reset     Force complete reset (delete and recreate deployment)"
    echo "  --verify    Only verify existing setup"
    echo "  --help      Show this help message"
    echo ""
    echo "This script will:"
    echo "  1. Check PostgreSQL pod status"
    echo "  2. Create spireuser and spiredb if they don't exist"
    echo "  3. Set up proper permissions"
    echo "  4. Verify the setup"
    echo ""
}

get_postgres_password() {
    log_info "Getting PostgreSQL admin password from secret..."

    if ! kubectl get secret -n $NAMESPACE postgresql-secret &> /dev/null; then
        log_error "PostgreSQL secret not found in namespace $NAMESPACE"
        exit 1
    fi

    POSTGRES_PASSWORD=$(kubectl get secret -n $NAMESPACE postgresql-secret -o jsonpath='{.data.password}' | base64 -d)

    if [ -z "$POSTGRES_PASSWORD" ]; then
        log_error "Could not retrieve PostgreSQL admin password from secret"
        exit 1
    fi

    log_success "Retrieved PostgreSQL admin password"
}

test_postgres_connection() {
    log_info "Testing PostgreSQL admin connection..."

    local test_result=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c "
        export PGPASSWORD='$POSTGRES_PASSWORD'
        psql -U $POSTGRES_USER -d postgres -c 'SELECT version();' > /dev/null 2>&1 && echo 'SUCCESS' || echo 'FAILED'
    ")

    if [ "$test_result" != "SUCCESS" ]; then
        log_error "Cannot connect to PostgreSQL as admin user"
        exit 1
    fi

    log_success "PostgreSQL admin connection successful"
}

check_existing_setup() {
    log_info "Checking existing database and user setup..."

    # Check if spiredb exists
    local db_exists=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c "
        export PGPASSWORD='$POSTGRES_PASSWORD'
        psql -U $POSTGRES_USER -d postgres -t -c \"SELECT 1 FROM pg_database WHERE datname='$SPIRE_DB';\" 2>/dev/null | grep -q 1 && echo 'YES' || echo 'NO'
    ")

    # Check if spireuser exists
    local user_exists=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c "
        export PGPASSWORD='$POSTGRES_PASSWORD'
        psql -U $POSTGRES_USER -d postgres -t -c \"SELECT 1 FROM pg_roles WHERE rolname='$SPIRE_USER';\" 2>/dev/null | grep -q 1 && echo 'YES' || echo 'NO'
    ")

    log_info "Database '$SPIRE_DB' exists: $db_exists"
    log_info "User '$SPIRE_USER' exists: $user_exists"

    if [ "$db_exists" = "YES" ] && [ "$user_exists" = "YES" ]; then
        return 0  # Both exist
    else
        return 1  # Need to create
    fi
}

create_spire_database_and_user() {
    log_info "Creating SPIRE database and user..."

    kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c "
        export PGPASSWORD='$POSTGRES_PASSWORD'
        psql -U $POSTGRES_USER -d postgres <<'EOF'
-- Drop existing if they exist (clean slate)
DROP DATABASE IF EXISTS $SPIRE_DB;
DROP USER IF EXISTS $SPIRE_USER;

-- Create spiredb database
CREATE DATABASE $SPIRE_DB;

-- Create spireuser with password
CREATE USER $SPIRE_USER WITH PASSWORD '$SPIRE_PASSWORD';

-- Grant database privileges
GRANT ALL PRIVILEGES ON DATABASE $SPIRE_DB TO $SPIRE_USER;

-- Connect to spiredb and set schema permissions
\\c $SPIRE_DB

-- Grant schema-level privileges
GRANT ALL ON SCHEMA public TO $SPIRE_USER;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $SPIRE_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $SPIRE_USER;

-- Grant future object privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $SPIRE_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $SPIRE_USER;

-- Create useful extensions for SPIRE
CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";
CREATE EXTENSION IF NOT EXISTS \"pgcrypto\";

-- Output success message
\\echo 'SPIRE database and user created successfully!'
EOF
    " || {
        log_error "Failed to create SPIRE database and user"
        return 1
    }

    log_success "SPIRE database and user created successfully"
}

verify_spire_setup() {
    log_info "Verifying SPIRE database setup..."

    # Test spireuser connection
    local connection_test=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c "
        PGPASSWORD='$SPIRE_PASSWORD' psql -h localhost -U $SPIRE_USER -d $SPIRE_DB -c 'SELECT current_user, current_database();' > /dev/null 2>&1 && echo 'SUCCESS' || echo 'FAILED'
    ")

    if [ "$connection_test" != "SUCCESS" ]; then
        log_error "spireuser cannot connect to spiredb"
        return 1
    fi

    # Verify permissions
    local permission_test=$(kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c "
        PGPASSWORD='$SPIRE_PASSWORD' psql -h localhost -U $SPIRE_USER -d $SPIRE_DB -c 'CREATE TABLE test_table (id SERIAL); DROP TABLE test_table;' > /dev/null 2>&1 && echo 'SUCCESS' || echo 'FAILED'
    ")

    if [ "$permission_test" != "SUCCESS" ]; then
        log_error "spireuser does not have proper permissions on spiredb"
        return 1
    fi

    log_success "SPIRE database setup verification passed"
    return 0
}

show_connection_info() {
    log_info "Connection Information:"
    echo ""
    echo "  Database: $SPIRE_DB"
    echo "  Username: $SPIRE_USER"
    echo "  Password: $SPIRE_PASSWORD"
    echo ""
    echo "  Connection String:"
    echo "  postgresql://$SPIRE_USER:$SPIRE_PASSWORD@postgresql:5432/$SPIRE_DB?sslmode=disable"
    echo ""
}

show_verification_commands() {
    log_info "Manual verification commands:"
    echo ""
    echo "  # List databases:"
    echo "  kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c \"PGPASSWORD='$POSTGRES_PASSWORD' psql -U $POSTGRES_USER -c '\\l'\""
    echo ""
    echo "  # List users:"
    echo "  kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c \"PGPASSWORD='$POSTGRES_PASSWORD' psql -U $POSTGRES_USER -c '\\du'\""
    echo ""
    echo "  # Test spireuser connection:"
    echo "  kubectl exec -n $NAMESPACE deployment/$DEPLOYMENT -- bash -c \"PGPASSWORD='$SPIRE_PASSWORD' psql -h localhost -U $SPIRE_USER -d $SPIRE_DB -c 'SELECT version();'\""
    echo ""
}

force_reset() {
    log_warning "Starting complete PostgreSQL reset..."

    # Delete PostgreSQL deployment
    log_info "Deleting PostgreSQL deployment..."
    kubectl delete deployment $DEPLOYMENT -n $NAMESPACE

    # Wait for termination
    log_info "Waiting for pod termination..."
    kubectl wait --for=delete pod -l app=postgresql -n $NAMESPACE --timeout=120s

    # Recreate deployment
    log_info "Recreating PostgreSQL deployment..."
    terraform apply -target=module.postgresql[0].kubernetes_deployment.postgresql -auto-approve

    # Wait for new pod to be ready
    log_info "Waiting for new PostgreSQL pod to be ready..."
    kubectl wait --for=condition=ready pod -l app=postgresql -n $NAMESPACE --timeout=300s

    # Give PostgreSQL time to fully start
    log_info "Waiting for PostgreSQL to fully start..."
    sleep 30

    log_success "PostgreSQL reset complete"
}

main() {
    local reset_flag=false
    local verify_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reset)
                reset_flag=true
                shift
                ;;
            --verify)
                verify_only=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "=========================================="
    echo "PostgreSQL SPIRE Setup Script"
    echo "=========================================="

    if [ "$reset_flag" = true ]; then
        force_reset
    fi

    get_postgres_password

    test_postgres_connection

    if [ "$verify_only" = true ]; then
        log_info "Running verification only..."
        if check_existing_setup && verify_spire_setup; then
            log_success "Verification passed - SPIRE database setup is correct"
            show_connection_info
        else
            log_error "Verification failed - SPIRE database setup needs fixing"
            exit 1
        fi
        exit 0
    fi

    if check_existing_setup; then
        log_info "SPIRE database and user already exist"
        if verify_spire_setup; then
            log_success "Existing setup is working correctly"
            show_connection_info
            exit 0
        else
            log_warning "Existing setup has issues, recreating..."
        fi
    fi

    create_spire_database_and_user

    if verify_spire_setup; then
        log_success "PostgreSQL SPIRE setup completed successfully!"
        show_connection_info
        show_verification_commands
    else
        log_error "Setup verification failed"
        exit 1
    fi

    echo "=========================================="
    log_success "Setup complete! SPIRE should now be able to connect to PostgreSQL."
    echo "=========================================="
}

main "$@"