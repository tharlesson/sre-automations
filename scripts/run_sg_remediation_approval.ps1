param(
    [ValidateSet("dev", "stage", "prod")]
    [string]$Environment = "dev",
    [string]$Region = "us-east-1",
    [string]$Project = "sreauto",
    [string]$Profile,
    [bool]$DryRun = $true,
    [bool]$RequireManualApproval = $true,
    [string]$Reason = "Aprovacao operacional SG remediation"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$awsCli = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
if (-not (Test-Path $awsCli)) {
    throw "AWS CLI nao encontrada em '$awsCli'."
}

$namePrefix = "$Project-$Environment-$Region"
$documentName = "$namePrefix-sg-remediation-approval"

$parameters = @{
    DryRun                = @($DryRun.ToString().ToLowerInvariant())
    RequireManualApproval = @($RequireManualApproval.ToString().ToLowerInvariant())
    Reason                = @($Reason)
}
$parametersJson = $parameters | ConvertTo-Json -Compress
$tempParametersFile = Join-Path $env:TEMP ("sg-remediation-parameters-" + [guid]::NewGuid().ToString() + ".json")
[System.IO.File]::WriteAllText(
    $tempParametersFile,
    $parametersJson,
    (New-Object System.Text.UTF8Encoding($false))
)

$args = @(
    "ssm",
    "start-automation-execution",
    "--region", $Region,
    "--document-name", $documentName,
    "--parameters", "file://$tempParametersFile"
)

if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $args += @("--profile", $Profile)
}

$rawResult = & $awsCli @args
if ($LASTEXITCODE -ne 0) {
    Remove-Item -Path $tempParametersFile -ErrorAction SilentlyContinue
    throw "Falha ao executar documento SSM '$documentName'."
}
$result = $rawResult | ConvertFrom-Json
Remove-Item -Path $tempParametersFile -ErrorAction SilentlyContinue

Write-Output "Documento SSM executado: $documentName"
Write-Output "AutomationExecutionId: $($result.AutomationExecutionId)"
