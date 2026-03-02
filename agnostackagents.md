# Agnostack Agents Runbook (Zendesk Shopify Premium)

This guide captures the fastest, most reliable workflow for testing draft-order behavior in the Agnostack-powered `Shopify Premium for Zendesk` app.

## Scope
- Store tested: `ehndwb-vu.myshopify.com` (SHP prod)
- Entry point: Zendesk ticket app panel/popup
- API path used by app: Zendesk Apps Proxy -> Shopify Admin GraphQL (`/admin/api/2026-01/graphql.json`)

## Fast Path Workflow
1. Open Zendesk ticket and launch **Shopify Premium for Zendesk** popup.
2. Confirm customer context is loaded: `kevin.wolf@swansonhealth.com`.
3. Create/select cart (`#Dxxxxx` draft order ID appears at top).
4. Add products from **Add Products to Cart**.
5. Apply promo code in cart (`CEO40SW`) and click **Apply**.
6. Validate cart totals and then validate GraphQL payload/response from DevTools Network.

## Efficient Product Add Behavior
- Use exact SKU search terms first (for example: `SWU375`).
- If search shows `No matching products found`, retry by:
  - refocusing the search combobox,
  - re-entering exact SKU,
  - clicking `Search` again.
- In some states, controls briefly disable after add/apply actions. Wait for re-enable before next action.

## Promo Behavior Lessons Learned
- Promo may not immediately show an explicit success banner.
- Reliable validation is the GraphQL `draftOrder` response, not only UI text.
- Confirm these response fields:
  - `platformDiscounts[].code` contains `CEO40SW`
  - `totalDiscountsSet.presentmentMoney.amount` is non-zero
  - `lineItems.edges[].node.quantity` reflects expected quantity updates

## GraphQL Evidence Pattern (From Live Test)
- Request type observed: `query getDraftOrder($id: ID!)`
- Draft example: `gid://shopify/DraftOrder/1241112281226` (`#D31845`)
- Verified in response:
  - promo code present under `platformDiscounts` as `CEO40SW`
  - line item quantity incremented to `2` for `SWU375`
  - request returned HTTP `200` via proxy endpoint

## Where To Inspect In DevTools
1. Open Network tab in Zendesk page DevTools.
2. Filter for `graphql.json`.
3. Open requests to:
   - `/api/v2/zendesk_apps_proxy/proxy/apps/secure/https%3A%2F%2Fehndwb-vu.myshopify.com%2Fadmin%2Fapi%2F2026-01%2Fgraphql.json`
4. Inspect both:
   - Request Body (mutation/query and variables)
   - Response Body (`userErrors`, discount nodes, lineItems, totals)

## Troubleshooting Checklist
- If UI appears stuck (buttons disabled, no navigation):
  - verify whether GraphQL requests are still succeeding (200 + valid response),
  - check if state actually changed server-side (quantity, discounts) despite stale UI.
- If expecting timeout reproduction:
  - compare this app profile to direct API scripts (payload size, query shape, update cadence),
  - include large selection sets only if reproducing app-like load profile.

## Test Logging Standard
- For every significant step, record:
  - draft order number and GID/legacy ID,
  - SKU(s) and quantities attempted,
  - promo applied and observed totals/discount,
  - relevant request IDs and response highlights.
- Post updates immediately to the active GitHub issue (real-time traceability).
