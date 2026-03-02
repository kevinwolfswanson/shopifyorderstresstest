# AGENTS.md

## Objective
- Keep this repository focused on Shopify draft-order stress testing.
- Preserve reproducible scripts, run parameters, and result interpretation.
- Prefer minimal, traceable changes.

## Current Project Scope
- Generate synthetic/fake Shopify products with unique SKUs.
- Stress test draft order creation using incremental SKU counts per order.
- Measure response latency and identify timeout/failure thresholds.

## Working Conventions
- Keep scripts PowerShell-first for local Windows execution.
- Avoid hardcoding secrets; use local key files or environment variables.
- Keep outputs (CSV/JSON) timestamped for run traceability.
- Document every material test run in `README.md` with:
  - run date/time
  - store target
  - SKU counts and iterations
  - timeout setting
  - pass/fail summary
  - basic latency metrics

## Test Workflow Standard
1. Seed fake SKUs/products.
2. Run incremental draft-order creation test:
   - line items per order: `1..N`
   - iterations per level: fixed (default `10`)
3. Persist raw results to CSV/JSON.
4. Summarize outcomes and threshold findings in README.

## Script Inventory (initial)
- `shopify_seed_fake_skus.ps1`: creates fake products/SKUs.
- `shopify_stress_draft_orders.ps1`: executes incremental draft-order stress test.
- `shopify_run_full_stress.ps1`: wrapper for seed + stress workflow.

## Safety and Secrets
- Never commit live access tokens.
- Never print secrets in logs.
- Keep token files outside this repository.

## Change Management
- Keep commits coherent and small.
- Push commits to GitHub immediately after creation.
- If behavior changes, update README in the same commit.
