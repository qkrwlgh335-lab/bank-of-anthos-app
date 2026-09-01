# AWS EKS migration notes

## What changed

- No Eureka dependency exists. Services use Kubernetes `ClusterIP` Services and cluster DNS names such as `userservice:8080`.
- PostgreSQL remains the only persistent database. Existing userservice DB tests use an in-memory SQLite database.
- Signup uses a Redis lock (`signup:<lowercase username>`) to serialize concurrent requests across userservice pods. PostgreSQL remains the source of truth and Redis never stores passwords or profiles.
- Runtime connection values are environment variables. `bank-app-secrets` is the stable Kubernetes Secret boundary that can later be populated from AWS Secrets Manager.

## Local/development deployment

Create the sample Secret, Redis, and the normal application manifests:

```bash
kubectl apply -f kubernetes-manifests/bank-app-secrets.example.yaml
kubectl apply -f kubernetes-manifests/redis.yaml
kubectl apply -f kubernetes-manifests/
```

Do not apply `external-secret.aws.example.yaml` until External Secrets Operator and the referenced `ClusterSecretStore` are installed. Do not use the example passwords in production.

## Production on EKS

Prefer Amazon RDS for PostgreSQL and ElastiCache for Redis. Put `REDIS_URL`, `ACCOUNTS_DB_URI`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` in the `/bank-of-anthos/application` Secrets Manager JSON object. Apply `external-secret.aws.example.yaml` after configuring External Secrets Operator with IRSA.

The in-cluster PostgreSQL and Redis manifests are development defaults, not highly available production data services.

## Tests

Userservice tests do not set `REDIS_URL`, so Redis is disabled and DB tests continue to use SQLite in memory. Production enables Redis by injecting `REDIS_URL` from `bank-app-secrets`.
