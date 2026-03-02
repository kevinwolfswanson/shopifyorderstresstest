param(
  [string]$StoreDomain = "xeuvzw-cz.myshopify.com",
  [string]$KeyFilePath = "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSC Shopify key.txt",
  [string]$AccessToken,
  [string]$ApiVersion = "2025-01",
  [int]$SkuCount = 100,
  [int]$Iterations = 10,
  [int]$TimeoutSec = 120,
  [switch]$CleanupDrafts,
  [string]$WorkDir = "."
)

$ErrorActionPreference = "Stop"

$seedScript = Join-Path $PSScriptRoot "shopify_seed_fake_skus.ps1"
$stressScript = Join-Path $PSScriptRoot "shopify_stress_draft_orders.ps1"

if (-not (Test-Path -LiteralPath $seedScript)) {
  throw "Missing script: $seedScript"
}
if (-not (Test-Path -LiteralPath $stressScript)) {
  throw "Missing script: $stressScript"
}

if (-not (Test-Path -LiteralPath $WorkDir)) {
  [void](New-Item -ItemType Directory -Path $WorkDir -Force)
}

$runId = Get-Date -Format "yyyyMMddHHmmss"
$seedCsv = Join-Path $WorkDir ("shopify_seed_results_{0}.csv" -f $runId)
$seedJson = Join-Path $WorkDir ("shopify_seed_results_{0}.json" -f $runId)
$stressCsv = Join-Path $WorkDir ("shopify_draft_stress_results_{0}.csv" -f $runId)
$stressJson = Join-Path $WorkDir ("shopify_draft_stress_results_{0}.json" -f $runId)

$seedArgs = @{
  StoreDomain = $StoreDomain
  KeyFilePath = $KeyFilePath
  ApiVersion = $ApiVersion
  Count = $SkuCount
  OutputCsv = $seedCsv
  OutputJson = $seedJson
}
if ($AccessToken) { $seedArgs.AccessToken = $AccessToken }

Write-Host "Step 1: Seeding $SkuCount fake SKUs/products..."
& $seedScript @seedArgs

$stressArgs = @{
  StoreDomain = $StoreDomain
  KeyFilePath = $KeyFilePath
  ApiVersion = $ApiVersion
  SeedCsvPath = $seedCsv
  MaxSkusPerOrder = $SkuCount
  Iterations = $Iterations
  TimeoutSec = $TimeoutSec
  OutputCsv = $stressCsv
  OutputJson = $stressJson
}
if ($AccessToken) { $stressArgs.AccessToken = $AccessToken }
if ($CleanupDrafts) { $stressArgs.CleanupDrafts = $true }

Write-Host "Step 2: Running stress test (1..$SkuCount SKUs per order, $Iterations iterations each)..."
& $stressScript @stressArgs

Write-Host "Completed full run."
Write-Host "Seed CSV: $seedCsv"
Write-Host "Seed JSON: $seedJson"
Write-Host "Stress CSV: $stressCsv"
Write-Host "Stress JSON: $stressJson"
