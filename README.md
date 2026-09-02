# Bank App on AWS EKS

Google의 오픈소스 샘플 Bank of Anthos를 AWS EKS 환경에 맞게 변경한 데모 은행 애플리케이션이다. 실제 금융 서비스가 아니므로 실제 개인정보나 금융정보를 입력하면 안 된다.

현재 Phase 1 PoC 구성은 EKS, ALB, ECR, RDS PostgreSQL, EKS 내부 Redis 및 AWS Secrets Manager를 사용한다. Eureka와 서비스 메시(Istio)는 사용하지 않는다.

실제로 검증한 GitHub Actions 흐름과 실행 증거는 [Phase 1 애플리케이션 CI](docs/phase1-cicd.md)에 정리했다.

> `infra/aws/dev`의 Terraform은 검증용 참고 구현이다. 실제 팀 환경에서는 네트워크, 보안, 가용성 및 비용 기준에 맞게 검토한 후 사용한다.

## 민감정보 처리

AWS 배포 코드에는 실제 AWS Access Key, RDS endpoint, Redis endpoint 또는 고정 비밀번호가 하드코딩되어 있지 않다.

- 환경 설정 예시는 `infra/aws/dev/terraform.tfvars.example`에 있다.
- 팀원은 이 파일을 `terraform.tfvars`로 복사해 환경별 값을 설정한다.
- 실제 `terraform.tfvars`는 Git에서 제외된다.
- DB와 Redis 비밀번호는 Git에서 제외된 `terraform.tfvars`의 sensitive 변수로 입력한다.
- DB와 Redis endpoint는 생성된 AWS 리소스에서 참조한다.
- 런타임 연결정보는 Secrets Manager와 Kubernetes Secret으로 전달한다.

```powershell
cd infra/aws/dev
Copy-Item terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars.example`의 `CHANGE_ME` 값을 실제 DB 비밀번호와 Redis token으로 교체한다. 실제 `terraform.tfvars`에는 비밀번호가 들어가므로 절대 커밋하거나 공유하지 않는다. Access Key와 생성된 DB/Redis endpoint는 넣지 않는다.

다음 파일은 Git이나 공유 ZIP에 포함하면 안 된다.

```text
terraform.tfvars
infra/aws/dev/terraform.tfstate*
infra/aws/dev/*.tfplan
infra/aws/dev/.terraform/
*.key
*.pem
kubeconfig-*
AWS credentials 파일
```

원본 GCP 예제인 `iac/` 아래에는 별도의 tfvars와 데모 설정이 남아 있지만 현재 AWS 배포에서는 사용하지 않는다. 원본 로컬 Kubernetes DB 매니페스트의 예제 계정도 AWS 배포 경로에서는 사용하지 않는다.

## 1. 앱 목적과 사용자 기능

마이크로서비스 기반 은행 업무 흐름을 AWS EKS에서 실행하고 검증하기 위한 앱이다.

- 회원가입
- 로그인 및 로그아웃
- 계좌번호와 현재 잔액 조회
- 거래 내역 조회
- 계좌 입금(Deposit Funds)
- 다른 계좌로 송금(Send Payment)
- 송금 대상 연락처 조회 및 추가

로그인 후에는 여러 메뉴 페이지 대신 하나의 계좌 대시보드에서 잔액, 입금, 송금, 거래 내역을 제공한다.

회원가입 시 Redis에서 사용자 이름 단위 분산 잠금을 획득한다. Redis는 동시 가입 요청 제어에만 사용하며 사용자 정보의 원본 저장소는 PostgreSQL이다.

## 2. 파일 구조와 역할

AWS 작업 시 아래 경로만 우선 확인하면 된다.

```text
bank-of-anthos-main/
├─ README.md                    이 문서
├─ kustomization.yaml          AWS EKS 배포 진입점
├─ src/                        실제 애플리케이션 코드
│  ├─ frontend/                웹 화면
│  ├─ accounts/
│  │  ├─ userservice/          가입·로그인·JWT·Redis 잠금
│  │  ├─ contacts/             송금 연락처
│  │  └─ accounts-db/          Accounts DB schema
│  └─ ledger/
│     ├─ ledgerwriter/         거래 기록
│     ├─ balancereader/        잔액 조회
│     ├─ transactionhistory/   거래 내역 조회
│     └─ ledger-db/            Ledger DB schema
├─ deploy/aws-eks/             AWS Ingress, 설정, DB 초기화 파일
├─ infra/aws/dev/              참고용 AWS Terraform
└─ kubernetes-manifests/       Deployment와 Service 원본
```

현재 AWS 배포에서 사용하지 않는 원본 참고 폴더:

```text
iac/       GCP/Anthos Terraform 및 CI/CD 예제
extras/    GKE, ASM, Cloud SQL 등의 추가 예제
docs/      원본 프로젝트 문서
```

Kustomize는 저장소 루트에서 실행한다.

```powershell
kubectl apply -k .
```

`deploy/aws-eks`에서 실행하면 상위 경로의 매니페스트를 읽지 못하는 Kustomize 보안 오류가 발생할 수 있다.

## 3. 6개 마이크로서비스 역할

| 서비스 | 기술 | 역할 |
| --- | --- | --- |
| `frontend` | Python/Flask | 로그인, 가입, 계좌 대시보드, 백엔드 호출 |
| `userservice` | Python/Flask | 회원가입, 로그인, JWT, Redis 가입 잠금 |
| `contacts` | Python/Flask | 송금 대상 연락처 조회 및 저장 |
| `ledgerwriter` | Java/Spring Boot | 입금과 송금 거래 검증 및 기록 |
| `balancereader` | Java/Spring Boot | 계좌 잔액 조회 |
| `transactionhistory` | Java/Spring Boot | 거래 내역 조회 |

데이터 저장소:

- Accounts DB: RDS PostgreSQL
- Ledger DB: RDS PostgreSQL
- 회원가입 잠금: EKS 내부 Redis Deployment

서비스 검색은 Eureka 대신 Kubernetes Service와 DNS를 사용한다. frontend는 `userservice:8080`, `ledgerwriter:8080`과 같은 이름으로 백엔드를 호출한다.

```text
Internet
  -> AWS ALB
  -> frontend ClusterIP Service
  -> frontend Pod
  -> 5개 backend Service
  -> RDS PostgreSQL / EKS 내부 Redis
```

## 4. Terraform 인프라 생성

필요 도구:

- AWS CLI v2
- Terraform
- Docker Desktop
- kubectl
- OpenSSL

```powershell
aws sts get-caller-identity --profile <AWS_PROFILE>

cd infra/aws/dev
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

이 저장소의 Terraform은 원본 참고 구현이다. 현재 PoC의 실제 VPC, EKS, managed node group, ECR, Secrets Manager와 add-on은 별도 GitOps 저장소의 Terraform이 관리한다.

팀 환경에서는 S3 remote state, state locking, VPC 주소, RDS Multi-AZ/backup, Redis failover, NAT Gateway 비용과 EKS node 크기를 별도로 결정한다.

```powershell
aws eks update-kubeconfig `
  --name <CLUSTER_NAME> `
  --region <AWS_REGION> `
  --profile <AWS_PROFILE>

kubectl get nodes
```

## 5. ECR 이미지 빌드 및 Push

저장소 루트에서 실행한다.

```powershell
.\deploy\aws-eks\build-and-push.ps1 `
  -AccountId <AWS_ACCOUNT_ID> `
  -Region <AWS_REGION> `
  -Tag <NEW_TAG> `
  -Profile <AWS_PROFILE>
```

스크립트는 6개 서비스 이미지를 각각 빌드해 `bank-app/<SERVICE>` ECR repository로 Push한다.

ECR tag는 immutable이므로 기존 태그를 덮어쓰지 않는다. 새 버전, Git commit SHA 또는 릴리스 버전을 사용한다.

Push 후 루트 `kustomization.yaml`의 ECR account ID, region 및 각 서비스 `newTag`를 팀 환경에 맞게 변경한다. 운영 배포는 가능하면 image digest로 고정한다.

## 6. ALB Controller

외부 요청은 AWS Load Balancer Controller가 생성한 ALB를 통해 frontend로 전달된다.

필수 구성:

- AWS Load Balancer Controller
- `kube-system/aws-load-balancer-controller` ServiceAccount
- Controller 전용 IAM role과 IAM policy
- EKS Pod Identity association
- cluster name, AWS region 및 VPC ID Controller 인자
- `alb` IngressClass

노드 IAM role에 Controller 권한을 직접 추가하는 대신 EKS Pod Identity를 권장한다.

```powershell
kubectl rollout status deployment/aws-load-balancer-controller `
  -n kube-system --timeout=180s

kubectl get pods -n kube-system `
  -l app.kubernetes.io/name=aws-load-balancer-controller

kubectl get ingressclass alb
```

`deploy/aws-eks/ingress.yaml`은 인터넷 공개 ALB와 IP Target을 사용한다.

```yaml
alb.ingress.kubernetes.io/scheme: internet-facing
alb.ingress.kubernetes.io/target-type: ip
```

## 7. PostgreSQL·Redis·Secret 구성

애플리케이션은 다음 Kubernetes Secret을 참조한다.

`bank-app-secrets`:

```text
ACCOUNTS_DB_URI
SPRING_DATASOURCE_URL
SPRING_DATASOURCE_USERNAME
SPRING_DATASOURCE_PASSWORD
REDIS_URL
```

`jwt-key`:

```text
jwtRS256.key
jwtRS256.key.pub
```

DB와 Redis 비밀번호는 현재 Git에서 제외된 `terraform.tfvars`로 Terraform에 전달되고, Terraform이 AWS Secrets Manager runtime secret에 저장한다. 애플리케이션에는 External Secrets Operator를 통해 Kubernetes Secret으로 동기화하는 방식을 권장한다. YAML, `.env` 또는 Git에는 실제 값을 저장하지 않는다.

JWT 키 생성 예시:

```powershell
openssl genrsa -out jwtRS256.key 4096
openssl rsa -in jwtRS256.key -pubout -out jwtRS256.key.pub

kubectl create secret generic jwt-key -n bank-app `
  --from-file=jwtRS256.key `
  --from-file=jwtRS256.key.pub
```

private key는 Git에 추가하지 말고 안전한 비밀 저장소로 이동하거나 사용 후 삭제한다.

DB schema:

```text
src/accounts/accounts-db/initdb/0-accounts-schema.sql
src/ledger/ledger-db/initdb/0_init_tables.sql
```

개발 환경에서는 `deploy/aws-eks/db-init-job.yaml`을 참고한다. 운영 환경에서는 별도 DB migration 절차를 권장한다.

테스트 DB는 인메모리 SQLite이고 운영 DB는 PostgreSQL이다.

## 8. Kubernetes 배포와 검증

배포 전 ECR 이미지 tag, `bank-app-secrets`, `jwt-key`, DB schema 및 ALB Controller 상태를 확인한다.

저장소 루트에서 실행한다.

```powershell
kubectl apply -k .
```

```powershell
kubectl get deployments,pods,services -n bank-app
kubectl get ingress -n bank-app
kubectl get targetgroupbindings -n bank-app
```

정상 기준:

- 6개 Deployment `READY 1/1`
- 애플리케이션 Pod 모두 `Running`
- 애플리케이션 Service 모두 `ClusterIP`
- Ingress에 ALB 주소 표시
- TargetGroupBinding `TARGET-TYPE`이 `ip`
- AWS Target Group의 frontend Pod IP가 `healthy`

```powershell
$AlbHost = kubectl get ingress bank-app -n bank-app `
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

curl.exe "http://$AlbHost/ready"
curl.exe -I "http://$AlbHost/"
```

기대 결과:

- `/ready`: HTTP 200 및 `ok`
- `/`: 로그인 화면 또는 계좌 화면
- 회원가입 및 로그인 성공
- 동일 사용자 이름 재가입 차단
- 입금과 송금 후 잔액 및 거래 내역 반영

userservice 로컬 테스트:

```powershell
cd src/accounts/userservice
uv sync
uv run pytest
```

운영 공개 전에는 ACM 인증서와 HTTPS, NetworkPolicy, 로그·메트릭·알람 및 데이터 백업 정책을 추가해야 한다. EKS, NAT Gateway, RDS 및 ALB는 실행 중 비용이 발생한다.
