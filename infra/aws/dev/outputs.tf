output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "ecr_urls" { value = { for k, v in aws_ecr_repository.app : k => v.repository_url } }
output "rds_endpoint" { value = aws_db_instance.postgres.address }
output "redis_endpoint" { value = aws_elasticache_replication_group.redis.primary_endpoint_address }
output "runtime_secret_arn" { value = aws_secretsmanager_secret.runtime.arn }
