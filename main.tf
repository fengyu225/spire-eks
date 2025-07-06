# Local values for consistent naming and tagging
locals {
  cluster_name = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "SPIRE"
    ManagedBy   = "Terraform"
  }
}

# =============================================================================
# VPC - Virtual Private Cloud
# =============================================================================
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  tags = local.common_tags
}

# =============================================================================
# SSH KEY PAIR - For EC2 access
# =============================================================================
resource "tls_private_key" "main" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = "${local.cluster_name}-key"
  public_key = tls_private_key.main.public_key_openssh
  tags       = local.common_tags
}

# =============================================================================
# EKS CLUSTER - Kubernetes cluster for SPIRE
# =============================================================================
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # EKS Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  # EKS Managed Node Group
  eks_managed_node_groups = {
    spire = {
      name = "${local.cluster_name}-spire-nodes"

      instance_types = [var.node_instance_type]

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_capacity

      disk_size = 50
      disk_type = "gp3"

      labels = {
        Environment = var.environment
        NodeGroup   = "spire"
        Purpose     = "spire-workload"
      }

      tags = local.common_tags
    }
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # PostgreSQL access from nodes
    ingress_postgresql = {
      description = "PostgreSQL access from nodes"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  enable_cluster_creator_admin_permissions = true

  tags = local.common_tags
}

# =============================================================================
# EBS CSI DRIVER IAM ROLE - For persistent storage
# =============================================================================
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

# =============================================================================
# S3 BUCKET - For SPIRE bundle storage and OIDC discovery
# =============================================================================
resource "aws_s3_bucket" "spire_bundle" {
  bucket = "${local.cluster_name}-spire-bundle"
  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-spire-bundle"
  })
}

resource "aws_s3_bucket_public_access_block" "spire_bundle" {
  bucket = aws_s3_bucket.spire_bundle.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "spire_bundle" {
  bucket = aws_s3_bucket.spire_bundle.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.spire_bundle.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.spire_bundle]
}

resource "aws_s3_bucket_cors_configuration" "spire_bundle" {
  bucket = aws_s3_bucket.spire_bundle.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_versioning" "spire_bundle" {
  bucket = aws_s3_bucket.spire_bundle.id
  versioning_configuration {
    status = "Enabled"
  }
}

# OIDC Discovery configuration
resource "aws_s3_object" "openid_configuration" {
  bucket       = aws_s3_bucket.spire_bundle.id
  key          = ".well-known/openid-configuration"
  content_type = "application/json"

  content = jsonencode({
    issuer                                = "https://${aws_s3_bucket.spire_bundle.bucket}.s3.${data.aws_region.current.name}.amazonaws.com"
    jwks_uri                              = "https://${aws_s3_bucket.spire_bundle.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/keys"
    response_types_supported              = ["id_token"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["RS256", "ES256"]
    token_endpoint_auth_methods_supported = ["none"]
    claims_supported                      = ["sub", "aud", "exp", "iat", "iss", "jti"]
    scopes_supported                      = ["openid"]
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-openid-config"
  })

  depends_on = [
    aws_s3_bucket_policy.spire_bundle,
    aws_s3_bucket_cors_configuration.spire_bundle
  ]
}

# =============================================================================
# SPIRE SERVER IAM ROLE - For S3 bundle publishing
# =============================================================================
resource "aws_iam_role" "spire_server" {
  name = "${local.cluster_name}-spire-server"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:spire:spire-server"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "spire_server" {
  name = "spire-bundle-s3-policy"
  role = aws_iam_role.spire_server.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::${aws_s3_bucket.spire_bundle.bucket}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::${aws_s3_bucket.spire_bundle.bucket}"
      }
    ]
  })
}

# =============================================================================
# KUBERNETES NAMESPACE - For SPIRE components
# =============================================================================
resource "kubernetes_namespace" "spire" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name = "spire"
  }

  depends_on = [module.eks]
}

# =============================================================================
# POSTGRESQL MODULE - Database for SPIRE
# =============================================================================
module "postgresql" {
  count  = var.deploy_kubernetes_resources ? 1 : 0
  source = "./modules/postgresql"

  cluster_name = local.cluster_name
  namespace    = kubernetes_namespace.spire[0].metadata[0].name

  database_name = "postgres"
  username      = "postgres"
  password      = "postgres"

  spire_database_name = var.spire_database_name
  spire_username      = var.spire_database_username
  spire_password      = var.spire_database_password

  storage_size = var.postgresql_storage_size

  tags = local.common_tags

  depends_on = [
    module.eks,
    kubernetes_namespace.spire
  ]
}

# =============================================================================
# KUBERNETES SERVICE ACCOUNTS - For SPIRE components
# =============================================================================
resource "kubernetes_service_account" "spire_server" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name      = "spire-server"
    namespace = kubernetes_namespace.spire[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.spire_server.arn
    }
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.spire,
    aws_iam_role.spire_server
  ]
}

resource "kubernetes_service_account" "spire_agent" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name      = "spire-agent"
    namespace = kubernetes_namespace.spire[0].metadata[0].name
  }

  depends_on = [
    module.eks,
    kubernetes_namespace.spire
  ]
}

resource "kubernetes_service_account" "oidc_provider" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name      = "oidc-provider"
    namespace = "oidc-provider"
  }

  depends_on = [
    module.eks
  ]
}

resource "kubernetes_namespace" "oidc_provider" {
  count = var.deploy_kubernetes_resources ? 1 : 0

  metadata {
    name = "oidc-provider"
    labels = {
      name = "oidc-provider"
    }
  }

  depends_on = [module.eks]
}