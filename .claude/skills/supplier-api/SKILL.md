---
name: supplier-api
description: Reference for Makerstorage's supplier catalog integrations (Mouser Search + Order/Cart APIs, DigiKey Product Information v4 + 3-legged OAuth Order Status v4) and the SSRF-guarded asset downloader. Use when touching app/services/supplier_catalog*, the DigiKey OAuth controller, part lookup/import, order import, push-to-cart, or remote datasheet/image attachment.
---

All supplier integration code lives in `app/services/supplier_catalog.rb` and `app/services/supplier_catalog/`. Read the file you're changing before editing — endpoints and payload shapes are documented inline.

## Architecture

- `SupplierCatalog.lookup(organization, mpn:)` → `Array<PartResult>` merged across every configured provider (`providers_for`). One provider failing doesn't sink the lookup; an error is raised only if *all* fail and nothing was found.
- Errors: everything raises a subclass of `SupplierCatalog::Error` — `NotConfiguredError` (no credentials) or `LookupError` (network/auth/bad payload). Controllers rescue `LookupError` and show `e.message` as a flash, so messages must be **user-actionable** ("Check it in Settings → Integrations…"), never raw stack traces or secrets.
- Normalized value objects: `PartResult` (`part_result.rb`), `OrderResult`, `OrderLineResult`, `CartResult` (in `supplier_catalog.rb`). Providers map their payloads onto these; controllers never read raw provider JSON. `DescriptionParser` extracts value/tolerance/package from free-text descriptions.
- Supplier records: an org's Mouser/DigiKey `Supplier` rows are identified by `catalog_provider` (unique per org), seeded on org creation (`Organization#seed_catalog_suppliers`).

## Mouser (`mouser.rb`)

- Search: `POST https://api.mouser.com/api/v1/search/keyword` with the **Search API key** (`organization.mouser_api_key`).
- Order import + cart: `ORDER_API_BASE = https://api.mouser.com/api/v1` with the separate **Order API key** (`mouser_order_api_key`). Build the client via `SupplierCatalog.mouser_order_client(org)` (nil when not configured).
- Push-to-cart only works for lines with a known Mouser part number; others are reported as skipped.
- Errors come back in an `"Errors"` array even on HTTP 200 — `check_for_errors!` handles it.
- Prices are localized strings (`"€0,05"`); parse via the existing helpers, don't re-implement.

## DigiKey (`digikey.rb`)

- Product search: `products/v4/search/keyword`, authenticated with a **2-legged client-credentials** token (cached; `token_cache_key`).
- Order Status: `orderstatus/v4/salesorder` is **user-scoped** → needs the **3-legged OAuth** flow in `Oauth::DigikeyController` (`/oauth/digikey/authorize` → DigiKey consent → `/oauth/digikey/callback`). The `state` param is stored in session and compared on callback — keep that check.
- Tokens (`digikey_access_token`, `digikey_refresh_token`, `digikey_token_expires_at`) live encrypted on `Organization`. `SupplierCatalog.digikey_order_client` refreshes an expired token first and persists the **rotated** refresh token (DigiKey rotates it on every refresh — losing it disconnects the account).
- Endpoint history: the order-status endpoint has been fixed twice (commits `941236d`, `05b8357`); verify against DigiKey's v4 docs before changing URLs.

## Credentials & secrets

- All keys/tokens are `encrypts` attributes on `Organization`; never log them, never put them in Inertia props, never return them in error messages.
- Keys are **write-only** in Settings (`SettingsController`): props expose only presence booleans (e.g. `mouser_api_key_present`); a blank submission keeps the stored value, and an explicit `remove_*` flag clears it. Follow the same pattern for any new credential.
- Only org **admins** can view/change integrations or run OAuth (`verify_organization_admin`).

## Remote assets — always through `RemoteFile`

Datasheet/image URLs come from lookup results relayed through the browser, so they're attacker-controllable. Download only via `SupplierCatalog::RemoteFile.download(url)`: http(s) only, every resolved IP must be public, the connection is pinned to the validated IP (`http.ipaddr = ip`, anti DNS-rebinding), each redirect hop re-checked (max 3), 25 MB cap, browser-like headers for Mouser's Akamai. Never use `URI.open`, `Net::HTTP.get`, or `Down` on these URLs. Attachment runs async in `AttachRemotePartAssetsJob`; a failed download must never break part creation.

## Tests

Never hit the network in tests. Stub at the provider boundary — e.g. `provider.define_singleton_method(:perform_request) { |_body| payload }` (see `test/services/supplier_catalog/mouser_test.rb`) or `stub_singleton(SupplierCatalog::Digikey, :post_token, ->(*) { {...} })` from `test/test_helper.rb` (Minitest 6 has no `minitest/mock`). Use trimmed real-shaped payloads, and cover: field mapping, empty results, auth error → `LookupError` with an actionable message, malformed JSON.
