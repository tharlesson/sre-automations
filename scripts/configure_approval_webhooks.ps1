param(
    [ValidateSet("dev", "stage", "prod")]
    [string]$Environment = "dev",
    [string]$ChatOpsWebhookUrl,
    [string]$ITSMWebhookUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ChatOpsWebhookUrl) -and [string]::IsNullOrWhiteSpace($ITSMWebhookUrl)) {
    throw "Informe ao menos um webhook: -ChatOpsWebhookUrl e/ou -ITSMWebhookUrl."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetFile = Join-Path $repoRoot "env/$Environment/terraform.local.tfvars"

$chatOpsLiteral = if ([string]::IsNullOrWhiteSpace($ChatOpsWebhookUrl)) { "null" } else { '"' + $ChatOpsWebhookUrl + '"' }
$itsmLiteral = if ([string]::IsNullOrWhiteSpace($ITSMWebhookUrl)) { "null" } else { '"' + $ITSMWebhookUrl + '"' }

$content = @(
    "# Local-only secrets (do not commit)."
    "approval_bridge_chatops_webhook_url = $chatOpsLiteral"
    "approval_bridge_itsm_webhook_url    = $itsmLiteral"
)

Set-Content -Path $targetFile -Value ($content -join "`r`n") -Encoding UTF8

Write-Output "Arquivo atualizado: $targetFile"
Write-Output "Use plan/apply com var-file adicional:"
Write-Output "terraform plan  -var-file=../../env/$Environment/terraform.tfvars -var-file=../../env/$Environment/terraform.local.tfvars"
Write-Output "terraform apply -var-file=../../env/$Environment/terraform.tfvars -var-file=../../env/$Environment/terraform.local.tfvars"
