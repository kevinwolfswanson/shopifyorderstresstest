# March 3, 2026: Lag/Retry + Metafield Test Status

This note consolidates latest stress-test outcomes and caveats.

## Scope
- Stores:
  - CSC: `xeuvzw-cz.myshopify.com`
  - SHP prod: `ehndwb-vu.myshopify.com`
- Customer context: `kevin.wolf@swansonhealth.com`
- Method: `draftOrderCreate` + `draftOrderUpdate` with pacing/retry

## CSC Results (Complete)

### Baseline with lag+retry (1..50)
- No promo artifact:
  - `output/csc_nopromo_1_to_50_lag_retry.csv`
- Promo artifact (`R6DTMXQYSV86`):
  - `output/csc_promo_1_to_50_lag_retry.csv`
- Summary:
  - No promo: `50/50` phase1 and `50/50` phase2 successful, no drops, no run errors
  - Promo: `50/50` discount present after phase1 and phase2, no drops, no run errors

### Metafield hypothesis test (CSC only)
- Injection script:
  - `output/csc_add_product_metafields.py`
- Injection artifact:
  - `output/csc_metafield_injection_summary.csv`
- Injected load:
  - 20 products
  - 100 fake product metafields each
  - 2,000 metafields created, 0 failed

### CSC post-injection retest (1..50)
- No promo artifact:
  - `output/csc_nopromo_1_to_50_lag_retry_meta.csv`
- Promo artifact:
  - `output/csc_promo_1_to_50_lag_retry_meta.csv`
- Summary:
  - No promo: `50/50` successful, no drops, no run errors
  - Promo: discount present `50/50` after phase1 and phase2, no drops, no run errors

### Important caveat on metafield test cohort
- Metafields were added to 20 products used by the ladder selection.
- The 1..50 SKU ladder is a mixed cohort:
  - includes SKUs from metafield-heavy products
  - and SKUs from products without injected metafields
- Result still indicates no measurable regression from injected product metafields under this execution profile.

## SHP Results (Latest Available)

### SHP no promo sequential run (complete)
- Artifact:
  - `output/shp_nopromo_1_to_50_lag_retry_seq.csv`
- Summary:
  - `50/50` phase1 and `50/50` phase2 successful
  - no drops
  - no run errors

### SHP promo sequential run (incomplete data set)
- Artifact:
  - `output/shp_promo_1_to_50_lag_retry_seq.csv`
- Current file state:
  - missing `sku_count` 44-50
  - resumed writes introduced duplicate rows for some counts
- Interpretation:
  - use this file as partial/intermediate only
  - run should be rerun cleanly for a definitive SHP promo 1..50 result set

## Issue Traceability
- CSC tracking issue:
  - https://github.com/kevinwolfswanson/shopifyorderstresstest/issues/1
- Zendesk/Agnostack and SHP behavior issue:
  - https://github.com/kevinwolfswanson/shopifyorderstresstest/issues/4
