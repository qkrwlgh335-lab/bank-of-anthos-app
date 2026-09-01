param(
    [Parameter(Mandatory = $true)][string]$AccountId,
    [Parameter(Mandatory = $true)][string]$Region,
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Profile = "target"
)

$ErrorActionPreference = 'Stop'
$registry = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$services = @(
    @{ Name = 'balancereader'; Path = 'src/ledger/balancereader' },
    @{ Name = 'contacts'; Path = 'src/accounts/contacts' },
    @{ Name = 'frontend'; Path = 'src/frontend' },
    @{ Name = 'ledgerwriter'; Path = 'src/ledger/ledgerwriter' },
    @{ Name = 'transactionhistory'; Path = 'src/ledger/transactionhistory' },
    @{ Name = 'userservice'; Path = 'src/accounts/userservice' }
)

$password = aws ecr get-login-password --profile $Profile --region $Region
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($password)) {
    throw "Failed to get an ECR login password"
}
docker login --username AWS --password $password $registry
if ($LASTEXITCODE -ne 0) { throw "ECR login failed" }

foreach ($service in $services) {
    $repository = "bank-app/$($service.Name)"
    aws ecr describe-repositories --profile $Profile --region $Region --repository-names $repository 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        aws ecr create-repository --profile $Profile --region $Region --repository-name $repository | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to create ECR repository $repository" }
    }
    $image = "$registry/${repository}:$Tag"
    docker build -t $image $service.Path
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed for $($service.Name)" }
    docker push $image
    if ($LASTEXITCODE -ne 0) { throw "Docker push failed for $($service.Name)" }
}
