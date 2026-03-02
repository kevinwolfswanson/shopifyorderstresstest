param(
  [string]$StoreDomain = "xeuvzw-cz.myshopify.com",
  [string]$KeyFilePath = "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSC Shopify key.txt",
  [string]$AccessToken,
  [string]$ApiVersion = "2025-01",
  [string]$SeedCsvPath = ".\shopify_seed_results.csv",
  [int]$MaxSkusPerOrder = 100,
  [int]$Iterations = 10,
  [int]$TimeoutSec = 120,
  [switch]$CleanupDrafts,
  [string]$OutputCsv = ".\shopify_draft_stress_results.csv",
  [string]$OutputJson = ".\shopify_draft_stress_results.json"
)

$ErrorActionPreference = "Stop"

function Read-KeyFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Key file not found: $Path"
  }

  $pairs = @{}
  Get-Content -LiteralPath $Path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or -not $line.Contains(':')) { return }

    $kv = $line.Split(':', 2)
    $key = $kv[0].Trim().ToLowerInvariant()
    $val = $kv[1].Trim()
    if ($key) { $pairs[$key] = $val }
  }

  return $pairs
}

function Get-AccessToken {
  param(
    [string]$Token,
    [string]$Path
  )

  if ($Token) { return $Token }

  $keys = Read-KeyFile -Path $Path
  if ($keys['access_token']) { return $keys['access_token'] }
  if ($keys['admin_access_token']) { return $keys['admin_access_token'] }
  if ($keys['token']) { return $keys['token'] }

  throw "No access token found. Add access_token to key file or pass -AccessToken."
}

function Invoke-Shopify {
  param(
    [string]$Domain,
    [string]$Token,
    [string]$Version,
    [string]$Method,
    [string]$Endpoint,
    [object]$Payload,
    [int]$Timeout = 120
  )

  $uri = "https://$Domain/admin/api/$Version$Endpoint"
  $headers = @{ "X-Shopify-Access-Token" = $Token }

  if ($Method -eq "POST") {
    $json = $Payload | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec $Timeout
  }

  if ($Method -eq "DELETE") {
    return Invoke-RestMethod -Method Delete -Uri $uri -Headers $headers -TimeoutSec $Timeout
  }

  throw "Unsupported method: $Method"
}

if (-not (Test-Path -LiteralPath $SeedCsvPath)) {
  throw "Seed CSV not found: $SeedCsvPath"
}

$token = Get-AccessToken -Token $AccessToken -Path $KeyFilePath
$seedRows = Import-Csv -LiteralPath $SeedCsvPath | Where-Object { $_.status -eq "ok" -and $_.variant_id }

if (-not $seedRows -or $seedRows.Count -eq 0) {
  throw "No valid variant_id rows found in seed CSV."
}

$usableCount = [Math]::Min($MaxSkusPerOrder, $seedRows.Count)
$selectedRows = $seedRows | Select-Object -First $usableCount
$runId = Get-Date -Format "yyyyMMddHHmmss"
$results = New-Object System.Collections.Generic.List[object]

for ($itemCount = 1; $itemCount -le $usableCount; $itemCount++) {
  $lineItems = @()
  $subset = $selectedRows | Select-Object -First $itemCount

  foreach ($row in $subset) {
    $lineItems += @{
      variant_id = [int64]$row.variant_id
      quantity = 1
    }
  }

  for ($iter = 1; $iter -le $Iterations; $iter++) {
    $draftId = $null
    $status = "ok"
    $errorText = $null

    $payload = @{
      draft_order = @{
        note = "stress-test run=$runId items=$itemCount iter=$iter"
        tags = "stress-test,run-$runId"
        line_items = $lineItems
      }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
      $resp = Invoke-Shopify -Domain $StoreDomain -Token $token -Version $ApiVersion -Method "POST" -Endpoint "/draft_orders.json" -Payload $payload -Timeout $TimeoutSec
      $draftId = $resp.draft_order.id

      if ($CleanupDrafts -and $draftId) {
        [void](Invoke-Shopify -Domain $StoreDomain -Token $token -Version $ApiVersion -Method "DELETE" -Endpoint "/draft_orders/$draftId.json" -Payload $null -Timeout $TimeoutSec)
      }
    } catch {
      $status = "error"
      $errorText = $_.Exception.Message
    }

    $stopwatch.Stop()

    $result = [PSCustomObject]@{
      run_id = $runId
      timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
      sku_count = $itemCount
      iteration = $iter
      status = $status
      elapsed_ms = $stopwatch.ElapsedMilliseconds
      draft_order_id = $draftId
      cleaned_up = [bool]$CleanupDrafts
      timeout_sec = $TimeoutSec
      error = $errorText
    }

    $results.Add($result)
    Write-Host ("items={0} iter={1}/{2} status={3} elapsed_ms={4}" -f $itemCount, $iter, $Iterations, $status, $stopwatch.ElapsedMilliseconds)
  }
}

$results | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputJson -Encoding UTF8

$okCount = ($results | Where-Object { $_.status -eq "ok" }).Count
$errCount = ($results | Where-Object { $_.status -eq "error" }).Count

Write-Host "Completed draft-order stress test."
Write-Host "Usable SKUs: $usableCount"
Write-Host "Iterations per SKU count: $Iterations"
Write-Host "Total attempts: $($usableCount * $Iterations)"
Write-Host "Success: $okCount"
Write-Host "Errors: $errCount"
Write-Host "CSV: $OutputCsv"
Write-Host "JSON: $OutputJson"
