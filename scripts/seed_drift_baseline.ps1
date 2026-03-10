param(
    [ValidateSet("dev", "stage", "prod")]
    [string]$Environment = "dev",
    [string]$Region,
    [string]$Profile,
    [string]$Application,
    [string[]]$SsmParameterPrefix = @(),
    [switch]$EnablePublishOnFirstApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TfvarsStringValue {
    param(
        [string]$Path,
        [string]$Key
    )
    $line = Select-String -Path $Path -Pattern ("^\s*" + [regex]::Escape($Key) + "\s*=\s*""([^""]*)""\s*$") | Select-Object -First 1
    if (-not $line) {
        return $null
    }
    $match = [regex]::Match($line.Line, "=\s*""([^""]*)""")
    if (-not $match.Success) {
        return $null
    }
    return $match.Groups[1].Value
}

function Set-TfvarsLiteralValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$LiteralValue
    )
    $content = Get-Content -Path $Path -Raw
    $pattern = "(?m)^(\s*" + [regex]::Escape($Key) + "\s*=\s*).*$"
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, ('${1}' + $LiteralValue))
    }
    else {
        $content = $content.TrimEnd() + "`r`n" + "$Key = $LiteralValue" + "`r`n"
    }
    Set-Content -Path $Path -Value $content -Encoding UTF8
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tfvarsFile = Join-Path $repoRoot "env/$Environment/terraform.tfvars"

if (-not (Test-Path $tfvarsFile)) {
    throw "Arquivo nao encontrado: $tfvarsFile"
}

if ([string]::IsNullOrWhiteSpace($Region)) {
    $Region = Get-TfvarsStringValue -Path $tfvarsFile -Key "region"
}
if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = Get-TfvarsStringValue -Path $tfvarsFile -Key "aws_profile"
}
if ([string]::IsNullOrWhiteSpace($Application)) {
    $Application = Get-TfvarsStringValue -Path $tfvarsFile -Key "application"
}

if ([string]::IsNullOrWhiteSpace($Region)) {
    throw "Nao foi possivel determinar a regiao (region)."
}

$pythonExe = "C:\Users\tharl\AppData\Local\Programs\Python\Python312\python.exe"
if (-not (Test-Path $pythonExe)) {
    $pythonExe = "python"
}

$args = @(
    (Join-Path $repoRoot "drift/generate_baseline_from_aws.py"),
    "--region", $Region,
    "--environment", $Environment,
    "--output", (Join-Path $repoRoot "drift/baseline.initial.json")
)
if (-not [string]::IsNullOrWhiteSpace($Profile)) {
    $args += @("--profile", $Profile)
}
if (-not [string]::IsNullOrWhiteSpace($Application)) {
    $args += @("--application", $Application)
}
foreach ($prefix in $SsmParameterPrefix) {
    if (-not [string]::IsNullOrWhiteSpace($prefix)) {
        $args += @("--ssm-parameter-prefix", $prefix)
    }
}

Write-Output "Gerando baseline real: environment=$Environment region=$Region profile=$Profile"
& $pythonExe @args
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao gerar baseline real."
}

if ($EnablePublishOnFirstApply) {
    Set-TfvarsLiteralValue -Path $tfvarsFile -Key "drift_detection_publish_initial_baseline" -LiteralValue "true"
    Set-TfvarsLiteralValue -Path $tfvarsFile -Key "drift_detection_initial_baseline_file_path" -LiteralValue '"../../drift/baseline.initial.json"'
    Write-Output "Flags de primeiro apply atualizadas em: $tfvarsFile"
}

Write-Output "Baseline pronta em: $(Join-Path $repoRoot 'drift/baseline.initial.json')"
