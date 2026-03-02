param(
  [string]$StoreDomain,
  [string]$KeyFilePath = "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSCshopifyadmin.txt",
  [string]$AccessToken,
  [string]$ApiVersion = "2025-01",
  [string]$CustomerEmail = "kevin.wolf@swansonhealth.com",
  [int]$MaxSkusPerOrder = 100,
  [int]$Iterations = 10,
  [int]$TimeoutSec = 120,
  [int]$VariantPoolSize = 200,
  [int]$PauseMs = 0,
  [switch]$CleanupDrafts,
  [string]$OutputCsv = ".\shopify_draft_stress_existing_catalog.csv",
  [string]$OutputJson = ".\shopify_draft_stress_existing_catalog.json",
  [string]$VariantsSnapshotCsv = ".\shopify_existing_variants_snapshot.csv"
)

$ErrorActionPreference = "Stop"

function Get-AccessToken {
  param(
    [string]$Token,
    [string]$Path
  )

  if ($Token) { return $Token.Trim() }
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Token file not found: $Path"
  }

  $raw = (Get-Content -LiteralPath $Path -Raw).Trim()
  if (-not $raw) {
    throw "Token file is empty: $Path"
  }

  if ($raw -match "(?im)^\s*(access_token|admin_access_token|token)\s*:\s*(.+)$") {
    return $Matches[2].Trim()
  }

  return $raw
}

function Invoke-Shopify {
  param(
    [string]$Domain,
    [string]$Token,
    [string]$Version,
    [ValidateSet("GET", "POST", "DELETE")]
    [string]$Method,
    [string]$Endpoint,
    [object]$Payload,
    [int]$Timeout = 120
  )

  $uri = "https://$Domain/admin/api/$Version$Endpoint"
  $headers = @{ "X-Shopify-Access-Token" = $Token }

  if ($Method -eq "GET") {
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec $Timeout
  }

  if ($Method -eq "POST") {
    $json = $Payload | ConvertTo-Json -Depth 30
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec $Timeout
  }

  return Invoke-RestMethod -Method Delete -Uri $uri -Headers $headers -TimeoutSec $Timeout
}

function Get-Variants {
  param(
    [string]$Domain,
    [string]$Token,
    [string]$Version,
    [int]$TargetCount,
    [int]$Timeout = 120
  )

  $variants = New-Object System.Collections.Generic.List[object]
  $sinceId = 0

  while ($variants.Count -lt $TargetCount) {
    $endpoint = "/variants.json?limit=250&since_id=$sinceId&fields=id,sku,title,inventory_policy,inventory_quantity"
    $resp = Invoke-Shopify -Domain $Domain -Token $Token -Version $Version -Method "GET" -Endpoint $endpoint -Payload $null -Timeout $Timeout

    if (-not $resp.variants -or $resp.variants.Count -eq 0) {
      break
    }

    foreach ($v in $resp.variants) {
      if (-not $v.id) { continue }
      if ([string]::IsNullOrWhiteSpace($v.sku)) { continue }

      $isOrderable = $true
      if ($v.inventory_policy -ne "continue" -and $null -ne $v.inventory_quantity -and [int]$v.inventory_quantity -le 0) {
        $isOrderable = $false
      }

      if ($isOrderable) {
        $variants.Add([PSCustomObject]@{
          variant_id = [int64]$v.id
          sku = $v.sku
          title = $v.title
          inventory_policy = $v.inventory_policy
          inventory_quantity = $v.inventory_quantity
        })
      }

      if ($variants.Count -ge $TargetCount) {
        break
      }
    }

    $sinceId = [int64]$resp.variants[-1].id
  }

  return $variants
}

if (-not $StoreDomain) {
  throw "StoreDomain is required for production mode. Example: swansonvitamins.myshopify.com"
}

$token = Get-AccessToken -Token $AccessToken -Path $KeyFilePath
$variants = Get-Variants -Domain $StoreDomain -Token $token -Version $ApiVersion -TargetCount $VariantPoolSize -Timeout $TimeoutSec

if (-not $variants -or $variants.Count -eq 0) {
  throw "No orderable variants found in store catalog."
}

$variants | Export-Csv -LiteralPath $VariantsSnapshotCsv -NoTypeInformation -Encoding UTF8

$usableCount = [Math]::Min($MaxSkusPerOrder, $variants.Count)
$selectedRows = $variants | Select-Object -First $usableCount
$runId = Get-Date -Format "yyyyMMddHHmmss"
$results = New-Object System.Collections.Generic.List[object]

for ($itemCount = 1; $itemCount -le $usableCount; $itemCount++) {
  $subset = $selectedRows | Select-Object -First $itemCount
  $lineItems = @()

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
        note = "stress-test existing-catalog run=$runId items=$itemCount iter=$iter"
        tags = "stress-test,existing-catalog,run-$runId"
        line_items = $lineItems
        customer = @{ email = $CustomerEmail }
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
      store_domain = $StoreDomain
      customer_email = $CustomerEmail
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

    if ($PauseMs -gt 0) {
      Start-Sleep -Milliseconds $PauseMs
    }
  }
}

$results | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputJson -Encoding UTF8

$okCount = ($results | Where-Object { $_.status -eq "ok" }).Count
$errCount = ($results | Where-Object { $_.status -eq "error" }).Count

Write-Host "Completed production draft-order stress test."
Write-Host "Store: $StoreDomain"
Write-Host "Customer email: $CustomerEmail"
Write-Host "Variant pool discovered: $($variants.Count)"
Write-Host "Usable SKUs: $usableCount"
Write-Host "Iterations per SKU count: $Iterations"
Write-Host "Total attempts: $($usableCount * $Iterations)"
Write-Host "Success: $okCount"
Write-Host "Errors: $errCount"
Write-Host "Variants snapshot: $VariantsSnapshotCsv"
Write-Host "CSV: $OutputCsv"
Write-Host "JSON: $OutputJson"
