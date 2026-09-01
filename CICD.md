# Bank of Anthos 애플리케이션 CI

이 저장소는 애플리케이션 소스와 CI만 소유합니다. EKS 및 Kubernetes desired state는
`qkrwlgh335-lab/bank-of-anthos-gitops` 저장소가 소유합니다.

## 배포 흐름

1. PR에서 변경된 서비스만 단위 테스트, 컨테이너 빌드, Trivy 검사를 수행합니다.
2. `main` 병합 후 동일 이미지를 한 번 빌드하고 `sha-<commit>` 불변 태그를 붙입니다.
3. GitHub OIDC로 AWS CI 역할을 맡아 ECR에 푸시합니다. 액세스 키는 저장하지 않습니다.
4. Google Workload Identity Federation으로 GAR에도 같은 이미지를 푸시합니다.
5. 모든 선택 서비스가 성공한 뒤 GitOps 저장소의 이미지 태그만 변경합니다.
6. EKS 안의 Argo CD가 변경을 감지해 배포합니다. CI는 EKS 권한을 갖지 않습니다.

서비스별 경로는 `frontend`, `userservice`, `contacts`, `balancereader`,
`ledgerwriter`, `transactionhistory` 여섯 개입니다. 서비스 하나만 바뀌면 그 서비스만
빌드·배포되며, 모든 서비스는 같은 EKS 클러스터 안에서 각각 별도 Deployment/Service로
실행됩니다.

필요한 GitHub 설정은 플랫폼 저장소의 `docs/github-setup.md`를 따릅니다.

Trivy는 모든 HIGH/CRITICAL 결과를 Actions 로그에 기록하고 CRITICAL 발견 시 publish를
차단합니다. HIGH는 이 PoC에서 가시화 대상으로 두며, 운영 전에는 수정 SLA와 예외 승인
절차를 정한 뒤 차단 대상으로 승격합니다.
