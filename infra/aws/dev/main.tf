data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  repositories = toset([
    "balancereader", "contacts", "frontend",
    "ledgerwriter", "transactionhistory", "userservice"
  ])
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.5.1"

  name = var.name
  cidr = "10.40.0.0/16"
  azs  = local.azs

  public_subnets = ["10.40.0.0/20", "10.40.16.0/20"]

  enable_nat_gateway      = false
  enable_dns_support      = true
  enable_dns_hostnames    = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.2"

  name                                     = var.name
  kubernetes_version                       = "1.36"
  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    app = {
      instance_types = var.node_instance_types
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      capacity_type  = "ON_DEMAND"
    }
  }
}

resource "aws_ecr_repository" "app" {
  for_each             = local.repositories
  name                 = "bank-app/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
  force_delete = true
}

resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = module.vpc.public_subnets
}

resource "aws_security_group" "database" {
  name_prefix = "${var.name}-postgres-"
  vpc_id      = module.vpc.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "database_from_nodes" {
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_db_instance" "postgres" {
  identifier              = var.name
  engine                  = "postgres"
  engine_version          = "17"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  max_allocated_storage   = 50
  storage_type            = "gp3"
  db_name                 = "postgres"
  username                = var.db_admin_username
  password                = var.db_admin_password
  port                    = 5432
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.database.id]
  publicly_accessible     = false
  multi_az                = false
  storage_encrypted       = true
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
}

resource "aws_elasticache_subnet_group" "main" {
  name       = var.name
  subnet_ids = module.vpc.public_subnets
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-redis-"
  vpc_id      = module.vpc.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_nodes" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = var.name
  description                = "Signup locking for ${var.name}"
  engine                     = "redis"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.redis.id]
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = var.redis_auth_token
  automatic_failover_enabled = false
  apply_immediately          = true
}

resource "aws_secretsmanager_secret" "runtime" {
  name                    = "/bank-app/runtime"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = aws_secretsmanager_secret.runtime.id
  secret_string = jsonencode({
    DB_ADMIN_USERNAME = aws_db_instance.postgres.username
    DB_ADMIN_PASSWORD = var.db_admin_password
    DB_HOST           = aws_db_instance.postgres.address
    DB_PORT           = tostring(aws_db_instance.postgres.port)
    REDIS_HOST        = aws_elasticache_replication_group.redis.primary_endpoint_address
    REDIS_PORT        = "6379"
    REDIS_AUTH_TOKEN  = var.redis_auth_token
  })
}
