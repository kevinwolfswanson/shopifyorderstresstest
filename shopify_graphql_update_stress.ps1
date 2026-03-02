param(
  [string]$CscDomain = "xeuvzw-cz.myshopify.com",
  [string]$CscTokenFile = "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSCshopifyadmin.txt",
  [string]$ShpDomain = "ehndwb-vu.myshopify.com",
  [string]$ShpTokenFile = "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\shopifytoken.txt",
  [string]$ApiVersion = "2025-01",
  [string]$CustomerEmail = "kevin.wolf@swansonhealth.com",
  [string]$PromoCode = "CEO40SW",
  [int]$MinSkus = 5,
  [int]$MaxSkus = 40,
  [int]$Step = 5,
  [int]$Iterations = 10,
  [int]$TimeoutSec = 120,
  [string]$OutputDir = ".\output"
)

$ErrorActionPreference = "Stop"

function Get-Token {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Token file not found: $Path"
  }

  $raw = (Get-Content -LiteralPath $Path -Raw).Trim()
  if (-not $raw) { throw "Token file empty: $Path" }

  if ($raw -match "(?im)^\s*(access_token|admin_access_token|token)\s*:\s*(.+)$") {
    return $Matches[2].Trim()
  }

  return $raw
}

function Invoke-ShopifyRest {
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
    $json = $Payload | ConvertTo-Json -Depth 50
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec $Timeout
  }

  return Invoke-RestMethod -Method Delete -Uri $uri -Headers $headers -TimeoutSec $Timeout
}

function Invoke-ShopifyGraphql {
  param(
    [string]$Domain,
    [string]$Token,
    [string]$Version,
    [string]$Query,
    [hashtable]$Variables,
    [int]$Timeout = 120
  )

  $uri = "https://$Domain/admin/api/$Version/graphql.json"
  $headers = @{ "X-Shopify-Access-Token" = $Token }
  $payload = @{ query = $Query; variables = $Variables }
  $json = $payload | ConvertTo-Json -Depth 100
  return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType "application/json" -Body $json -TimeoutSec $Timeout
}

function Get-OrderableVariants {
  param(
    [string]$Domain,
    [string]$Token,
    [string]$Version,
    [int]$NeededCount,
    [int]$Timeout = 120
  )

  $rows = New-Object System.Collections.Generic.List[object]
  $sinceId = 0

  while ($rows.Count -lt $NeededCount) {
    $resp = Invoke-ShopifyRest -Domain $Domain -Token $Token -Version $Version -Method GET -Endpoint "/variants.json?limit=250&since_id=$sinceId&fields=id,sku,title,inventory_policy,inventory_quantity" -Payload $null -Timeout $Timeout
    if (-not $resp.variants -or $resp.variants.Count -eq 0) { break }

    foreach ($v in $resp.variants) {
      if (-not $v.id) { continue }
      if ([string]::IsNullOrWhiteSpace($v.sku)) { continue }

      $isOrderable = $true
      if ($v.inventory_policy -ne "continue" -and $null -ne $v.inventory_quantity -and [int]$v.inventory_quantity -le 0) {
        $isOrderable = $false
      }

      if ($isOrderable) {
        $rows.Add([PSCustomObject]@{
          variant_id = [int64]$v.id
          variant_gid = "gid://shopify/ProductVariant/$($v.id)"
          sku = $v.sku
          title = $v.title
        })
      }

      if ($rows.Count -ge $NeededCount) { break }
    }

    $sinceId = [int64]$resp.variants[-1].id
  }

  return $rows
}

function New-DraftViaRest {
  param(
    [string]$Domain,
    [string]$Token,
    [string]$Version,
    [int64]$VariantId,
    [string]$Email,
    [int]$Timeout = 120
  )

  $payload = @{
    draft_order = @{
      line_items = @(@{ variant_id = $VariantId; quantity = 1 })
      customer = @{ email = $Email }
      note = "graphql-update-stress bootstrap"
      tags = "stress-test,graphql-update"
    }
  }

  $resp = Invoke-ShopifyRest -Domain $Domain -Token $Token -Version $Version -Method POST -Endpoint "/draft_orders.json" -Payload $payload -Timeout $Timeout
  return $resp.draft_order.id
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  [void](New-Item -ItemType Directory -Path $OutputDir -Force)
}

$updateMutation = @'
mutation updateDraftOrder($id: ID!, $input: DraftOrderInput!) {
  draftOrderUpdate(id: $id, input: $input) {
    draftOrder {
      id
      legacyResourceId
      name
      createdAt
      updatedAt
      currencyCode
      presentmentCurrencyCode
      taxesIncluded
      totalPriceSet { presentmentMoney { amount currencyCode } }
      tags
      email
      phone
      taxExempt
      customer {
        id
        legacyResourceId
        firstName
        lastName
        state
        defaultEmailAddress { emailAddress marketingState }
        defaultPhoneNumber { phoneNumber marketingState }
      }
      billingAddress {
        address1
        address2
        city
        country
        phone
        province
        provinceCode
        zip
        id
        name
        company
        firstName
        lastName
        countryCodeV2
      }
      shippingAddress {
        address1
        address2
        city
        country
        phone
        province
        provinceCode
        zip
        id
        name
        company
        firstName
        lastName
        countryCodeV2
        validationResultSummary
      }
      totalTaxSet { presentmentMoney { amount currencyCode } }
      status
      invoiceUrl
      visibleToCustomer
      totalDiscountsSet { presentmentMoney { amount currencyCode } }
      customAttributes { key value }
      lineItems(first: 100) {
        pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
        edges {
          node {
            id
            sku
            quantity
            variantTitle
            variant {
              id
              legacyResourceId
              availableForSale
              inventoryPolicy
              inventoryQuantity
              sellableOnlineQuantity
              inventoryItem { tracked }
              displayName
            }
            image { url altText }
            originalTotalSet { presentmentMoney { amount currencyCode } }
            originalUnitPriceSet { presentmentMoney { amount currencyCode } }
            totalDiscountSet { presentmentMoney { amount currencyCode } }
            taxLines { priceSet { presentmentMoney { amount currencyCode } } }
            name
            title
            vendor
            isGiftCard
            customAttributes { key value }
            product {
              id
              legacyResourceId
              handle
              title
              vendor
              isGiftCard
              onlineStoreUrl
              onlineStorePreviewUrl
              requiresSellingPlan
              tracksInventory
              variantsCount { count precision }
            }
            custom
            weight { unit value }
            priceOverride { amount currencyCode }
            appliedDiscount {
              value
              valueType
              amountSet { presentmentMoney { amount currencyCode } }
            }
          }
        }
      }
      metafields(first: 3, namespace: "agnoStack-metadata") {
        pageInfo { hasNextPage hasPreviousPage startCursor endCursor }
        edges { node { key namespace type value } }
      }
    }
    userErrors { field message }
  }
}
'@

$scenarios = @(
  [PSCustomObject]@{ label = "CSC"; domain = $CscDomain; token = (Get-Token -Path $CscTokenFile); promo = $null },
  [PSCustomObject]@{ label = "SHP"; domain = $ShpDomain; token = (Get-Token -Path $ShpTokenFile); promo = $null },
  [PSCustomObject]@{ label = "SHP_PROMO"; domain = $ShpDomain; token = (Get-Token -Path $ShpTokenFile); promo = $PromoCode }
)

$allResults = New-Object System.Collections.Generic.List[object]
$runId = Get-Date -Format "yyyyMMddHHmmss"

foreach ($scenario in $scenarios) {
  Write-Host "=== Scenario: $($scenario.label) / $($scenario.domain) ==="

  $variantRows = Get-OrderableVariants -Domain $scenario.domain -Token $scenario.token -Version $ApiVersion -NeededCount $MaxSkus -Timeout $TimeoutSec
  if (-not $variantRows -or $variantRows.Count -lt $MaxSkus) {
    throw "Scenario $($scenario.label): insufficient orderable variants. Found=$($variantRows.Count) needed=$MaxSkus"
  }

  $variantSnapshot = Join-Path $OutputDir ("graphql_variants_{0}_{1}.csv" -f $scenario.label.ToLowerInvariant(), $runId)
  $variantRows | Export-Csv -LiteralPath $variantSnapshot -NoTypeInformation -Encoding UTF8

  for ($skuCount = $MinSkus; $skuCount -le $MaxSkus; $skuCount += $Step) {
    $subset = $variantRows | Select-Object -First $skuCount
    $lineItems = @()
    foreach ($v in $subset) {
      $lineItems += @{ quantity = 1; variantId = $v.variant_gid }
    }

    for ($iter = 1; $iter -le $Iterations; $iter++) {
      $draftId = $null
      $status = "ok"
      $errorKind = $null
      $errorText = $null
      $userErrors = $null
      $returnedLineItemCount = $null

      $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
      try {
        $draftId = New-DraftViaRest -Domain $scenario.domain -Token $scenario.token -Version $ApiVersion -VariantId ([int64]$subset[0].variant_id) -Email $CustomerEmail -Timeout $TimeoutSec
        $draftGid = "gid://shopify/DraftOrder/$draftId"

        $input = @{ lineItems = $lineItems; presentmentCurrencyCode = "USD" }
        if ($scenario.promo) {
          $input.customAttributes = @(@{ key = "promo_code"; value = $scenario.promo })
        }

        $resp = Invoke-ShopifyGraphql -Domain $scenario.domain -Token $scenario.token -Version $ApiVersion -Query $updateMutation -Variables @{ id = $draftGid; input = $input } -Timeout $TimeoutSec

        if ($resp.errors) {
          $status = "error"
          $errorKind = "graphql_errors"
          $errorText = ($resp.errors | ConvertTo-Json -Compress)
        } else {
          $ue = $resp.data.draftOrderUpdate.userErrors
          if ($ue -and $ue.Count -gt 0) {
            $status = "error"
            $errorKind = "user_errors"
            $userErrors = ($ue | ConvertTo-Json -Compress)
            $errorText = $userErrors
          }

          $edges = $resp.data.draftOrderUpdate.draftOrder.lineItems.edges
          $returnedLineItemCount = if ($edges) { $edges.Count } else { 0 }
          if ($status -eq "ok" -and $returnedLineItemCount -ne $skuCount) {
            $status = "error"
            $errorKind = "line_item_count_mismatch"
            $errorText = "expected=$skuCount actual=$returnedLineItemCount"
          }
        }
      } catch {
        $status = "error"
        $errorKind = "exception"
        $errorText = $_.Exception.Message
      } finally {
        if ($draftId) {
          try {
            [void](Invoke-ShopifyRest -Domain $scenario.domain -Token $scenario.token -Version $ApiVersion -Method DELETE -Endpoint "/draft_orders/$draftId.json" -Payload $null -Timeout $TimeoutSec)
          } catch {
            if ($status -eq "ok") {
              $status = "error"
              $errorKind = "cleanup_exception"
              $errorText = "cleanup_failed: $($_.Exception.Message)"
            }
          }
        }
      }

      $stopwatch.Stop()

      $row = [PSCustomObject]@{
        run_id = $runId
        scenario = $scenario.label
        store_domain = $scenario.domain
        customer_email = $CustomerEmail
        promo_code = $scenario.promo
        sku_count = $skuCount
        iteration = $iter
        status = $status
        error_kind = $errorKind
        error = $errorText
        user_errors = $userErrors
        elapsed_ms = $stopwatch.ElapsedMilliseconds
        returned_line_item_count = $returnedLineItemCount
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
      }

      $allResults.Add($row)
      Write-Host ("scenario={0} skus={1} iter={2}/{3} status={4} elapsed_ms={5}" -f $scenario.label, $skuCount, $iter, $Iterations, $status, $stopwatch.ElapsedMilliseconds)
    }
  }
}

$csvPath = Join-Path $OutputDir ("graphql_update_stress_results_{0}.csv" -f $runId)
$jsonPath = Join-Path $OutputDir ("graphql_update_stress_results_{0}.json" -f $runId)
$summaryPath = Join-Path $OutputDir ("graphql_update_stress_summary_{0}.csv" -f $runId)

$allResults | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
$allResults | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$summary = $allResults |
  Group-Object scenario, sku_count |
  ForEach-Object {
    $parts = $_.Name.Split(',')
    $scenario = $parts[0].Trim()
    $sku = [int]$parts[1].Trim()
    $rows = $_.Group
    $ok = ($rows | Where-Object { $_.status -eq "ok" }).Count
    $err = ($rows | Where-Object { $_.status -ne "ok" }).Count
    $m = $rows | Measure-Object elapsed_ms -Average -Minimum -Maximum

    [PSCustomObject]@{
      scenario = $scenario
      sku_count = $sku
      attempts = $rows.Count
      success = $ok
      errors = $err
      avg_elapsed_ms = [Math]::Round($m.Average, 2)
      min_elapsed_ms = $m.Minimum
      max_elapsed_ms = $m.Maximum
    }
  } | Sort-Object scenario, sku_count

$summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

$totalOk = ($allResults | Where-Object { $_.status -eq "ok" }).Count
$totalErr = ($allResults | Where-Object { $_.status -ne "ok" }).Count

Write-Host "Completed GraphQL update stress run."
Write-Host "Results CSV: $csvPath"
Write-Host "Results JSON: $jsonPath"
Write-Host "Summary CSV: $summaryPath"
Write-Host "Total attempts: $($allResults.Count)"
Write-Host "Success: $totalOk"
Write-Host "Errors: $totalErr"
