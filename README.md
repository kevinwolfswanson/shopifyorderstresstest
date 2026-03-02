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

## Recommended Next Test Expansion
To find failure boundary faster:
- Increase max line items beyond `100` (for example `150`, `200`, `300`).
- Optionally reduce timeout setting (for example `10`-`30` seconds) to surface practical limits.
- Continue using timestamped output folders for comparison across runs.

## Security Note
Do not commit access tokens or key files. Keep credentials in local files outside this repository.
