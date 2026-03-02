# Shopify Order Stress Test

Repository for repeatable stress testing of Shopify draft-order creation performance.

## Purpose
Validate draft-order creation behavior under increasing line-item load, using synthetic SKUs/products, and capture when timeouts or failures begin.

## Environment Initialization (Completed)
- Store target: `xeuvzw-cz.myshopify.com`
- API style: Shopify Admin REST API
- Local execution shell: PowerShell (Windows)
- Scripted workflow established for:
  - SKU seeding
  - incremental draft-order load testing
  - structured result export (CSV + JSON)

## Test Approach
1. Seed synthetic catalog items
- Create unique fake products with unique SKUs and descriptions.
- Default seed volume: `100` products/SKUs.
- Capture product + variant IDs for later draft-order line items.

2. Incremental draft-order stress test
- For each SKU count `k` from `1` to `N` (default `100`):
  - Create draft orders containing `k` line items
  - Repeat each `k` level for `10` iterations
- Record per attempt:
  - status
  - elapsed milliseconds
  - draft order ID
  - error (if any)

3. Results and threshold analysis
- Export detailed records to CSV/JSON.
- Compute success rate and latency trends by SKU count.
- Identify first timeout/failure boundary (if reached).

## Scripts
- `shopify_seed_fake_skus.ps1`
  - Seeds fake products/SKUs.
  - Outputs seed results to CSV/JSON.

- `shopify_stress_draft_orders.ps1`
  - Executes incremental stress test for draft orders.
  - Supports iterations, timeout config, optional cleanup.

- `shopify_stress_existing_catalog.ps1`
  - Production-safe mode: uses existing store variants only.
  - No product/SKU creation.
  - Assigns draft orders to a known customer email.

- `shopify_run_full_stress.ps1`
  - End-to-end wrapper:
    1. seed SKUs
    2. run stress test

## Example Run
```powershell
powershell -ExecutionPolicy Bypass -File .\shopify_run_full_stress.ps1 `
  -AccessToken "<ADMIN_API_TOKEN>" `
  -SkuCount 100 `
  -Iterations 10 `
  -TimeoutSec 120 `
  -WorkDir .\output
```

## Discovery Notes (Current)
Initial full execution completed with these settings:
- Seed count: `100` SKUs
- Stress pattern: `1..100` line items per order
- Iterations per level: `10`
- Total draft-order create attempts: `1000`
- Request timeout setting: `120s`

Observed outcome:
- Seed success: `100/100`
- Draft-order create success: `1000/1000`
- Errors: `0`
- Timeouts: `0`
- End-to-end wall time: ~`19m 39s`

Latency snapshot from recorded results:
- Overall average: `~1102 ms`
- Overall min/max: `381 ms / 2387 ms`
- At `100` line items:
  - average: `~1804 ms`
  - min/max: `1411 ms / 2300 ms`

Conclusion from this run:
- No timeout threshold observed at up to `100` line items with `120s` timeout.

## Latest GraphQL Mimic Run (Agnostack Profile)
Run date: `2026-03-02`

Purpose:
- Mimic the heavy `draftOrderUpdate` GraphQL selection shape used by Agnostack/Zendesk.
- Test at fixed `40` SKUs with `10` iterations per scenario.

Configuration:
- Query profile: `agnostack` (heavy nested selection set)
- SKU count: `40` unique variants, quantity `1` each
- Iterations: `10`
- Customer email: `kevin.wolf@swansonhealth.com`
- SHP variants constrained to vendor matching `Swanson`
- SHP promo scenario uses GraphQL `discountCodes: [\"CEO40SW\"]`

Results:
- `CSC` (`xeuvzw-cz.myshopify.com`): `0/10` success, `10/10` errors
- `SHP` (`ehndwb-vu.myshopify.com`): `10/10` success, `0` errors
- `SHP_PROMO` (`ehndwb-vu.myshopify.com`): `10/10` success, `0` errors

Observed latency (successful SHP scenarios):
- SHP: approximately `3.4s` to `4.2s`
- SHP_PROMO: approximately `3.1s` to `4.1s`

Artifacts:
- `output/graphql_update_stress_results_20260302131040.csv`
- `output/graphql_update_stress_results_20260302131040.json`
- `output/graphql_update_stress_summary_20260302131040.csv`

## Recommended Next Test Expansion
To find failure boundary faster:
- Increase max line items beyond `100` (for example `150`, `200`, `300`).
- Optionally reduce timeout setting (for example `10`-`30` seconds) to surface practical limits.
- Continue using timestamped output folders for comparison across runs.

## Production Existing-Catalog Test Mode
Use this mode when testing on a production store that already has SKUs.

Example canary:
```powershell
powershell -ExecutionPolicy Bypass -File .\shopify_stress_existing_catalog.ps1 `
  -StoreDomain "<production-store>.myshopify.com" `
  -KeyFilePath "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSCshopifyadmin.txt" `
  -CustomerEmail "kevin.wolf@swansonhealth.com" `
  -MaxSkusPerOrder 10 `
  -Iterations 3 `
  -TimeoutSec 120 `
  -CleanupDrafts `
  -OutputCsv .\output\prod_canary.csv `
  -OutputJson .\output\prod_canary.json `
  -VariantsSnapshotCsv .\output\prod_variants_snapshot.csv
```

Example full run:
```powershell
powershell -ExecutionPolicy Bypass -File .\shopify_stress_existing_catalog.ps1 `
  -StoreDomain "<production-store>.myshopify.com" `
  -KeyFilePath "C:\Users\kevin.wolf\OneDrive - Swanson Health Products\CSCshopifyadmin.txt" `
  -CustomerEmail "kevin.wolf@swansonhealth.com" `
  -MaxSkusPerOrder 100 `
  -Iterations 10 `
  -TimeoutSec 120 `
  -CleanupDrafts `
  -OutputCsv .\output\prod_full.csv `
  -OutputJson .\output\prod_full.json `
  -VariantsSnapshotCsv .\output\prod_variants_snapshot.csv
```

## Security Note
Do not commit access tokens or key files. Keep credentials in local files outside this repository.
