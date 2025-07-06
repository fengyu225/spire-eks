# SPIRE on Amazon EKS

A complete Terraform-based solution for deploying SPIRE (Secure Production Identity Framework for Everyone) on Amazon EKS with PostgreSQL backend storage.

## Overview

This project provides a deployment of SPIRE on Amazon EKS, including:

- **AWS Infrastructure**: VPC, EKS cluster, IAM roles, S3 bucket for bundle storage
- **PostgreSQL Database**: Dedicated database for SPIRE server data storage
- **SPIRE Components**: Server, Agent, Controller Manager, and CSI Driver
- **Security**: RBAC, service accounts, and network policies
- **Observability**: Health checks and monitoring endpoints

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS Account                          │
├─────────────────────────────────────────────────────────────┤
│  VPC (10.0.0.0/16)                                          │
│  ├── Public Subnets (NAT, Load Balancers)                   │
│  └── Private Subnets (EKS Nodes, PostgreSQL)                │
│                                                             │
│  EKS Cluster                                                │
│  ├── Control Plane                                          │
│  └── Managed Node Groups (t3.medium)                        │
│                                                             │
│  S3 Bucket (SPIRE Bundle Storage)                           │
│  └── OIDC Discovery Configuration                           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
├─────────────────────────────────────────────────────────────┤
│  spire namespace:                                           │
│  ├── SPIRE Server (StatefulSet)                             │
│  ├── SPIRE Agent (DaemonSet)                                │
│  ├── SPIRE Controller Manager (Sidecar)                     │
│  ├── PostgreSQL (Deployment)                                │
│  └── SPIFFE CSI Driver (DaemonSet)                          │
│                                                             │
│  oidc-provider namespace:                                   │
│  └── OIDC Provider Service Account                          │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools

- **Terraform** >= 1.0
- **AWS CLI** >= 2.0 (configured with appropriate credentials)
- **kubectl** >= 1.28
- **bash** (for setup scripts)

### AWS Permissions

Your AWS credentials need permissions for:
- VPC and networking (subnets, route tables, NAT gateways)
- EKS cluster management
- IAM role and policy management
- S3 bucket operations
- EC2 instance management

### Terraform Cloud (Optional)

This project is configured to use Terraform Cloud with the workspace `spire` in organization `yu-feng-tfe`. Update `provider.tf` if using a different backend.

## Project Structure

```
.
├── main.tf                 # Main Terraform configuration
├── variables.tf            # Input variables with validation
├── outputs.tf              # Output values
├── provider.tf             # Provider and backend configuration
├── data.tf                 # Data sources
├── terraform.tfvars        # Variable values (customize for your environment)
├── setup-postgres.sh       # PostgreSQL setup and verification script
├── modules/
│   └── postgresql/         # PostgreSQL module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── spire/                  # Kubernetes manifests for SPIRE
    ├── kustomization.yaml  # Kustomize configuration
    ├── namespace.yaml      # Kubernetes namespaces
    ├── configmaps/         # Configuration files
    ├── deployments/        # Application deployments
    ├── rbac/              # Role-based access control
    ├── services/          # Kubernetes services
    ├── crds/              # Custom Resource Definitions
    └── upstreamca/        # Certificate Authority setup
```

## Deployment Guide

### Step 1: Configure Variables

1. Copy and customize the Terraform variables:
   ```bash
   cp terraform.tfvars terraform.tfvars.local
   ```

2. Edit `terraform.tfvars.local` with your specific values:
   ```hcl
   # AWS Configuration
   aws_region = "us-east-1"
   
   # Project Configuration
   project_name = "my-spire"
   environment  = "dev"
   
   # Network Configuration
   vpc_cidr           = "10.0.0.0/16"
   availability_zones = ["us-east-1a", "us-east-1b"]
   
   # EKS Configuration
   kubernetes_version = "1.32"
   node_instance_type = "t3.medium"
   desired_capacity   = 2
   
   # IMPORTANT: Start with false
   deploy_kubernetes_resources = false
   
   # SPIRE Configuration
   spire_trust_domain = "example.org"
   
   # PostgreSQL Configuration (use strong passwords in production)
   spire_database_name     = "spire"
   spire_database_username = "spire"
   spire_database_password = "your-secure-password-here"
   ```

### Step 2: Deploy AWS Infrastructure

First, deploy the AWS infrastructure without Kubernetes resources:

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -var-file="terraform.tfvars.local"

# Apply the configuration
terraform apply -var-file="terraform.tfvars.local"
```

This creates:
- VPC with public/private subnets
- EKS cluster with managed node groups
- S3 bucket for SPIRE bundle storage
- IAM roles and policies
- EBS CSI driver setup

### Step 3: Configure kubectl

Configure kubectl to access your new EKS cluster:

```bash
# Get cluster name from Terraform output
CLUSTER_NAME=$(terraform output -raw cluster_name)

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name $CLUSTER_NAME

# Verify connection
kubectl get nodes
```

### Step 4: Deploy PostgreSQL

Enable Kubernetes resource deployment and deploy PostgreSQL:

1. Update your tfvars file:
   ```hcl
   deploy_kubernetes_resources = true
   ```

2. Apply the changes:
   ```bash
   terraform apply -var-file="terraform.tfvars.local"
   ```

3. Verify PostgreSQL deployment:
   ```bash
   kubectl get pods -n spire
   kubectl logs -n spire deployment/postgresql
   ```

4. Set up SPIRE database (optional verification):
   ```bash
   ./setup-postgres.sh --verify
   ```

### Step 5: Create SPIRE Database Secret

Create the database secret that SPIRE will use:

```bash
# Create secrets.env file for Kustomize
cat > spire/secrets.env << EOF
DB_CONNECTION_STRING=postgresql://spire:your-secure-password-here@postgresql:5432/spire?sslmode=disable
EOF
```

### Step 6: Deploy SPIRE

Deploy SPIRE using Kustomize:

```bash
# Apply SPIRE manifests
kubectl apply -k spire/

# Wait for SPIRE server to be ready
kubectl wait --for=condition=ready pod -l app=spire-server -n spire --timeout=300s

# Wait for SPIRE agents to be ready
kubectl wait --for=condition=ready pod -l app=spire-agent -n spire --timeout=300s
```

### Step 7: Verify SPIRE Deployment

Check that all SPIRE components are running:

```bash
# Check all pods in spire namespace
kubectl get pods -n spire

# Check SPIRE server logs
kubectl logs -n spire statefulset/spire-server -c spire-server

# Check SPIRE agent logs
kubectl logs -n spire daemonset/spire-agent

# Check SPIRE server health
kubectl exec -n spire statefulset/spire-server -c spire-server -- \
  /opt/spire/bin/spire-server healthcheck

# List registration entries
kubectl exec -n spire statefulset/spire-server -c spire-server -- \
  /opt/spire/bin/spire-server entry show
```

## Configuration

### Key Configuration Files

- **`spire/configmaps/spire-server.yaml`**: SPIRE server configuration
- **`spire/configmaps/spire-agent.yaml`**: SPIRE agent configuration
- **`spire/cluster-spiffe-ids.yaml`**: SPIFFE ID templates for workloads

### Trust Domain

The default trust domain is `example.org`. Change this in:
- `terraform.tfvars` (`spire_trust_domain`)
- `spire/configmaps/controller-manager.yaml`
- `spire/configmaps/spire-server.yaml`
- `spire/configmaps/spire-agent.yaml`

### Database Configuration

PostgreSQL is deployed with:
- **Storage**: EmptyDir (ephemeral) - data lost on pod restart
- **Database**: `spire` (configurable)
- **User**: `spire` (configurable)
- **Connection**: Internal cluster networking only

⚠️ **Production Note**: The current PostgreSQL setup uses ephemeral storage. For production, modify the PostgreSQL module to use persistent volumes.

## SPIFFE ID Management

### Default SPIFFE IDs

The deployment creates these default SPIFFE ID templates:

1. **OIDC Provider**: `spiffe://example.org/oidc-provider`
2. **Default Workloads**: `spiffe://example.org/ns/{namespace}/sa/{service-account}`

### Creating Custom SPIFFE IDs

Create custom ClusterSPIFFEID resources:

```yaml
apiVersion: spire.spiffe.io/v1alpha1
kind: ClusterSPIFFEID
metadata:
  name: my-app
spec:
  spiffeIDTemplate: "spiffe://example.org/my-app"
  podSelector:
    matchLabels:
      app: my-app
  workloadSelectorTemplates:
    - "k8s:ns:default"
    - "k8s:sa:my-app"
```

## Troubleshooting

### Common Issues

1. **PostgreSQL Connection Issues**
   ```bash
   # Check PostgreSQL pod logs
   kubectl logs -n spire deployment/postgresql
   
   # Verify database setup
   ./setup-postgres.sh --verify
   
   # Reset PostgreSQL if needed
   ./setup-postgres.sh --reset
   ```

2. **SPIRE Server Connection Issues**
   ```bash
   # Check server logs
   kubectl logs -n spire statefulset/spire-server -c spire-server
   
   # Check database connection string
   kubectl get secret -n spire spire-database-secret -o yaml
   ```

3. **SPIRE Agent Registration Issues**
   ```bash
   # Check agent logs
   kubectl logs -n spire daemonset/spire-agent
   
   # Check server attestation logs
   kubectl logs -n spire statefulset/spire-server -c spire-server | grep attestation
   ```

### Health Checks

SPIRE server provides health check endpoints:

```bash
# Check liveness
kubectl exec -n spire statefulset/spire-server -c spire-server -- \
  curl -f http://localhost:8080/live

# Check readiness
kubectl exec -n spire statefulset/spire-server -c spire-server -- \
  curl -f http://localhost:8080/ready
```

### Useful Commands

```bash
# Port forward to SPIRE server
kubectl port-forward -n spire statefulset/spire-server 8081:8081

# Access SPIRE server API
kubectl exec -n spire statefulset/spire-server -c spire-server -- \
  /opt/spire/bin/spire-server entry show

# Check SPIRE bundle
kubectl get configmap -n spire spire-bundle -o yaml
```