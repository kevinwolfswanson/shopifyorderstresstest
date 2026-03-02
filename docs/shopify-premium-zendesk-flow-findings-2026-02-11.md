# Shopify Premium for Zendesk: Draft Order Flow Findings

**Author:** Codex
**Date of analysis:** February 11, 2026 (UTC)
**Primary page tested:** https://swansonhealthproducts.zendesk.com/agent/tickets/new/128?brand_id=43073659649683
**App under test:** Shopify Premium for Zendesk (Agnostack plugin-commerce 5.37.0)

## 1. Objective

Document, with concrete request-level evidence, what happens in the Shopify Premium draft-order flow when address and shipping are modified, and identify realistic timeout risk points.

## 2. Tools and Data Sources Used

- Chrome DevTools MCP
  - list_network_requests
  - get_network_request
  - page interactions in Zendesk agent ticket modal flow
- Captured request IDs and headers from the same browser session
- Timings taken from response headers where available:
  - cfRequestDuration
  - x-envoy-upstream-service-time
  - server-timing summary context

## 3. Test Context

- Tested a draft order with many line items and discounting activity.
- Evidence of high item/discount complexity in payloads:
  - lineItems(first: 100) requested in GraphQL mutations.
  - Multiple platformDiscounts returned in mutation responses.
  - Promo/discount code artifacts present in returned data.
- Shipping and address updates were exercised in the order workflow from Billing/Shipping through Review.

## 4. What I Did (Action-by-Action)

### 4.1 Reverted temporary address edits and re-ran flow

I reset temporary draft-order address edits, then walked the order flow again to capture clean timing behavior.

- Billing address set back to expected value
- Additional line address cleared
- Continued through order flow:
  - Billing -> Review
  - Review -> Share to Customer

### 4.2 Captured and analyzed network burst around address/shipping changes

I reviewed the specific request burst tied to address/shipping updates and shipping rate selection.

## 5. Request-Level Timeline and Measured Durations

The following are key requests from the captured flow (all on February 11, 2026 UTC) and what each represented.

| Req ID | Action Context | Endpoint | Measured Time | Notes |
|---|---|---|---:|---|
| 2007 | Initial app data bootstrap | Shopify GraphQL via Zendesk proxy | ~148ms | Lightweight lookup (getShopLocations) |
| 2009 | Draft refresh | Shopify GraphQL via Zendesk proxy | ~454ms | getDraftOrder |
| 2010 | Customer search | Shopify GraphQL via Zendesk proxy | ~210ms | searchCustomers |
| 2011 | Customer load | Shopify GraphQL via Zendesk proxy | ~187ms | getCustomer |
| 2012 | Address update mutation | Shopify GraphQL via Zendesk proxy | **~3571ms** | draftOrderUpdate (largest observed in burst) |
| 2013 | Draft refresh after mutation | Shopify GraphQL via Zendesk proxy | ~480ms | getDraftOrder |
| 2014 | Delivery-rate retrieval | Shopify GraphQL via Zendesk proxy | **~1880ms** | getDeliveryOptions |
| 2022 | Draft refresh | Shopify GraphQL via Zendesk proxy | ~660ms | getDraftOrder |
| 2023 | Shipping line selection mutation | Shopify GraphQL via Zendesk proxy | **~2120ms** | draftOrderUpdate with shipping line |
| 2024 | Draft refresh after shipping select | Shopify GraphQL via Zendesk proxy | ~456ms | getDraftOrder |
| 2025 | Agnostack extend/proxy pass | Agnostack -> AWS API Gateway Lambda | ~653ms upstream | oute=extend, status 200 |

### 5.1 Concrete example: heavy mutation during address change (eqid=2012)

- Operation: draftOrderUpdate
- Timing evidence:
  - cfRequestDuration;dur=3570.999861
  - x-envoy-upstream-service-time: 3601
- Interpretation:
  - Address-related mutation triggers full draft recalculation work, not a tiny patch operation.

### 5.2 Concrete example: shipping-rate selection mutation (eqid=2023)

- Operation: draftOrderUpdate with shipping line payload (shippingRateHandle, title token, and price)
- Timing evidence:
  - cfRequestDuration;dur=2119.999886
  - x-envoy-upstream-service-time: 2152
- Interpretation:
  - Shipping selection is another heavyweight update and can be multi-second on larger drafts.

## 6. Lambda Proxy Call Deep Dive (eqid=2025)

### 6.1 Endpoint chain observed

Browser request path:

- Zendesk secure app proxy endpoint
- Proxies to Agnostack endpoint (pi.agnostack.io/5-37-0/proxy/...)
- Agnostack proxies to AWS API Gateway:
  - https://tjmj91zye6.execute-api.us-east-1.amazonaws.com/prod/?route=extend

### 6.2 Security/transport characteristics observed

- Request body was an encoded/encrypted numeric array (large payload), not plain JSON in browser view.
- Headers included app-signing/envelope indicators such as:
  - x-authorization
  - x-public-key
  - x-ephemeral-key
- This is consistent with proxy-mediated secure transport and aligns with API key not being directly exposed in frontend code paths.

### 6.3 Performance characteristics

- Status: 200
- x-envoy-upstream-service-time: 653
- Conclusion:
  - In this capture, Lambda/proxy extend call is not the dominant latency source.
  - The slower calls were Shopify draft-order mutations and delivery option resolution.

## 7. Why Timeout Risk Exists in This Flow

Timeout risk is cumulative and sequencing-related, not just one request failing.

When an agent updates address/shipping in a large draft order, the app can trigger a chain like:

1. draftOrderUpdate (multi-second)
2. getDraftOrder
3. getDeliveryOptions (multi-second)
4. another draftOrderUpdate for shipping line (multi-second)
5. final getDraftOrder
6. auxiliary proxy/extend calls

With many SKUs plus promo/discount calculations, the chain is expensive. If the agent continues interacting before the chain settles, overlapping in-flight work can increase perceived slowness and error/timeout likelihood.

## 8. User-Experience Narrative (What the Agent Sees)

A practical user story from this behavior:

1. Agent opens a draft with many SKUs and a promo.
2. Agent updates shipping/billing details.
3. UI appears to continue responding, but behind the scenes multiple heavy GraphQL calls start.
4. Delivery options appear after recalculation delay.
5. Agent selects a shipping rate, which triggers another heavyweight mutation.
6. If the agent changes fields or navigates quickly during this period, they can experience intermittent lag, stale values, or apparent timeout-like behavior.

## 9. Key Conclusions

1. **Primary bottleneck is Shopify draft-order recalculation via GraphQL mutations**, especially on large discounted drafts.
2. **Lambda proxy oute=extend was healthy in this capture** (~653ms, 200), and not the top latency driver.
3. **Address/shipping changes can trigger a multi-call heavyweight transaction pattern**, not an isolated single lightweight call.
4. **Large cart + promo + repeated edits during in-flight requests** is a credible timeout/instability pattern.

## 10. Evidence Snippets (for quick reference)

- eqid=2012 (draftOrderUpdate) -> cfRequestDuration ~3571ms
- eqid=2014 (getDeliveryOptions) -> ~1880ms
- eqid=2023 (draftOrderUpdate shipping line) -> cfRequestDuration ~2120ms
- eqid=2025 (oute=extend) -> x-envoy-upstream-service-time: 653ms

## 11. Notes for Future AI Agents

When diagnosing this app in Zendesk:

1. Start from request IDs around the user action timestamp.
2. Separate calls into categories:
   - Shopify GraphQL mutations/queries
   - Agnostack proxy calls
   - Zendesk telemetry/background noise
3. Use header timing values first (cfRequestDuration, x-envoy-upstream-service-time) for fast triage.
4. Treat draftOrderUpdate as heavyweight in large carts.
5. Correlate user clicks with request bursts; do not assume one UI action maps to one network call.
6. If debugging timeouts, prioritize mutation overlap and sequence length before blaming Lambda.

---

If needed, I can append a second section that maps each visible UI control (address fields, shipping selector, review action, share action) to the exact request IDs observed when that control is used.

## Addendum: March 2, 2026 (Agnostack UI/API Mismatch Under High Draft Load)

### Scope
- Zendesk app: Shopify Premium for Zendesk (Agnostack)
- Store: `ehndwb-vu.myshopify.com`
- Customer context: `kevin.wolf@swansonhealth.com`
- Draft under test: `#D31778` (`gid://shopify/DraftOrder/1241105531018`)

### New Confirmed Findings
1. `draftOrderUpdate` can become materially slower at higher draft complexity.
- Captured mutation (`reqid=1277`) completed `200 OK` but took about `12.7s`.
- Header evidence:
  - `server-timing: processing;dur=12669`
  - `cfRequestDuration;dur=12754.999876`
- During this period, modal controls were temporarily disabled and appeared frozen.

2. Add Products UI can fail to render results while backend GraphQL search is returning matches.
- In-app UI showed `No matching products found` for search term `SWD0`.
- Simultaneous Shopify GraphQL response returned non-empty `products.edges`.
- Example returned SKUs/variants from `reqid=1301` (`query: sku:SWD0*`):
  - `SWD013` -> `gid://shopify/ProductVariant/46319060779146`
  - `SWD076` -> `gid://shopify/ProductVariant/46319060418698`
  - `SWD090` -> `gid://shopify/ProductVariant/46319060353162`

### Interpretation
- This extends the Feb 11 findings: latency remains a real factor, but there is also a reproducible frontend state/render failure mode in Add Products under high-line-item draft context.
- The `route=extend` path was not implicated as primary bottleneck during these reproductions.

### Traceability
- Logged live to GitHub issue #4:
  - https://github.com/kevinwolfswanson/shopifyorderstresstest/issues/4#issuecomment-3986809416
  - https://github.com/kevinwolfswanson/shopifyorderstresstest/issues/4#issuecomment-3986816645
  - https://github.com/kevinwolfswanson/shopifyorderstresstest/issues/4#issuecomment-3986820346
