param(
  [string]$StoreDomain = "xeuvzw-cz.myshopify.com",
  [string]$KeyFilePath = "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSC Shopify key.txt",
  [string]$AccessToken,
  [string]$ApiVersion = "2025-01",
  [int]$Count = 100,
  [int]$StartIndex = 1,
  [string]$SkuPrefix = "FAKE-STRESS",
  [string]$OutputCsv = ".\shopify_seed_results.csv",
  [string]$OutputJson = ".\shopify_seed_results.json"
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
    [int]$TimeoutSec = 120
  )

  $uri = "https://$Domain/admin/api/$Version$Endpoint"
  $headers = @{ "X-Shopify-Access-Token" = $Token }

  if ($Method -eq "GET") {
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec $TimeoutSec
  }

  if ($Method -eq "POST") {
    $json = $Payload | ConvertTo-Json -Depth 20
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec $TimeoutSec
  }

  throw "Unsupported method: $Method"
}

$token = Get-AccessToken -Token $AccessToken -Path $KeyFilePath
$runId = Get-Date -Format "yyyyMMddHHmmss"
$results = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $Count; $i++) {
  $index = $StartIndex + $i
  $sku = "{0}-{1}-{2:D4}" -f $SkuPrefix, $runId, $index
  $title = "Stress Test Product $sku"
  $description = "Synthetic product for draft-order stress testing. SKU: $sku. Run: $runId."

  $payload = @{
    product = @{
      title = $title
      body_html = "<p>$description</p>"
      vendor = "StressTest"
      product_type = "PerformanceTest"
      tags = "stress-test,fake-sku,run-$runId"
      variants = @(
        @{
          sku = $sku
          price = "1.00"
          taxable = $false
          requires_shipping = $false
          inventory_management = $null
          inventory_policy = "continue"
        }
      )
    }
  }

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $status = "ok"
  $errorText = $null
  $productId = $null
  $variantId = $null

  try {
    $resp = Invoke-Shopify -Domain $StoreDomain -Token $token -Version $ApiVersion -Method "POST" -Endpoint "/products.json" -Payload $payload
    $productId = $resp.product.id
    if ($resp.product.variants -and $resp.product.variants.Count -gt 0) {
      $variantId = $resp.product.variants[0].id
    }
  } catch {
    $status = "error"
    $errorText = $_.Exception.Message
  }

  $stopwatch.Stop()

  $row = [PSCustomObject]@{
    run_id = $runId
    created_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    sku = $sku
    title = $title
    description = $description
    product_id = $productId
    variant_id = $variantId
    status = $status
    elapsed_ms = $stopwatch.ElapsedMilliseconds
    error = $errorText
  }

  $results.Add($row)
  Write-Host ("[{0}/{1}] {2} -> {3}" -f ($i + 1), $Count, $sku, $status)
}

$results | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputJson -Encoding UTF8

$okCount = ($results | Where-Object { $_.status -eq "ok" }).Count
$errCount = ($results | Where-Object { $_.status -eq "error" }).Count

Write-Host "Completed seeding SKUs."
Write-Host "Success: $okCount"
Write-Host "Errors: $errCount"
Write-Host "CSV: $OutputCsv"
Write-Host "JSON: $OutputJson"
