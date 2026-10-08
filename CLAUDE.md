# Makerstorage

Electronics-parts inventory manager for makerspaces/fablabs: components, categories, footprints, storage zones, stock movements, suppliers, purchase orders, project BOMs, low-stock alerts — scoped per organization (multi-tenant).

## Stack
- **Backend**: Rails 8.1 (8.1.3), **SQLite** in every environment (production too, with Solid Cache/Queue/Cable on separate SQLite DBs — see `config/database.yml`), Devise (auth), Inertia Rails.
- **Frontend**: Inertia.js + React 19 + TypeScript, Vite, Tailwind v4.
- **Components**: shadcn/ui (`new-york` style, `neutral` base color, Lucide icons) — see `components.json`.
- Ruby 3.4.8, Node 24+.

## Frontend conventions
- The entire frontend is built on **shadcn/ui**. Use the existing components in [app/frontend/components/ui/](app/frontend/components/ui/) as-is wherever possible.
- Avoid modifying shadcn component internals or hand-rolling custom one-off components when an equivalent shadcn/Radix primitive already exists — compose existing components instead. Don't add new raw `<button>`/`<input>`/`<select>` elements in pages; use the `ui/` equivalents.
- Only add a new component (via shadcn or from scratch) when nothing in the current library covers the need.
- UI language is **English-first**. (There is a French-language design prototype in `design-makerstorage/` — treat it as a layout/behavior reference only, not a copy/language source.)

## Backend conventions
- Domain controllers `include Auth` and run `before_action :verify_organization_access`, then gate mutations with `verify_organization_writer` (blocks viewers), `verify_organization_admin`, or `verify_organization_owner` (all in `ApplicationController`).
- Always look records up through the tenant: `current_organization.parts.find(params[:id])`, never `Part.find`.
- Select-input payloads (categories, footprints, tags, suppliers, storage locations) come from the `OptionListSerializers` concern — reuse it rather than re-serializing.
- Return validation errors to Inertia forms with `inertia_errors(model, as: :resource)` so keys match the nested form data (`part.name`).
- **Every foreign key needs a matching `has_many … dependent:` on the parent** (`:restrict_with_error` when the child is history/ledger data). A missing one turns `.destroy` into an `ActiveRecord::InvalidForeignKey` 500 (SQLite enforces FKs).
- **Auth hardening**: Devise `:lockable` (10 failures → 15-minute lock, time-based unlock) plus per-IP `rate_limit` on sign-in, password reset, and sign-up (store: `ApplicationController::AUTH_RATE_LIMIT_STORE`; tests get a real store via `config.x.rate_limit_store`, cleared before each test). The reset form answers identically for known and unknown emails; changing the sign-in email requires the current password. Deleting a catalog supplier (Mouser/DigiKey) disconnects the integration and is admin-only.
- **Content Security Policy** (`config/initializers/content_security_policy.rb`) ships **report-only**; browsers post violations to `/csp-violations` (`CspReportsController`, logged as `[CSP] …`) — check those logs before switching to enforcement. Inline `<script>` tags must use `nonce: true` / `request.content_security_policy_nonce`; new external origins (fonts, images, APIs called from the browser) must be added to the policy. HTTPS is opt-in via `FORCE_SSL=true` (production), since LAN installs run on plain HTTP.
- Test helpers that read Inertia props parse `<script data-page="app" type="application/json" …>` — keep the `[^>]*` in that regex (the tag carries a nonce).
- Multi-record writes triggered by one action (purchase-order batches, bulk actions, CSV import rows) run in a transaction and turn `RecordInvalid` into a flash message rather than a 500.
- Roles per membership: `owner` > `admin` > `member` > `viewer`. Only **active, accepted** memberships grant access (`user.organizations` and the `*_of?` helpers go through `active_organization_memberships`, i.e. `OrganizationMembership.granting_access`). Adding a member from the Members page creates an **invitation** that grants nothing until the invitee accepts it from their profile (`InvitationsController`); memberships created directly (signup, new organization, seeds) carry no invitation. An organization must always keep at least one active owner.
- `Organization`'s `has_many … dependent: :destroy` declarations run in declaration order: records that reference others (movements, projects, orders) are declared before what they reference (parts, locations, suppliers). Keep that order when adding associations.

## Domain notes
- **Multi-tenancy**: every domain record (parts, categories, footprints, tags, suppliers, storage locations, stock movements, orders, projects) belongs to an `Organization` via `organization_id`. `current_organization` is resolved per-session in `ApplicationController`.
- **Signup auto-creates a personal organization** for every new user ([app/models/user.rb](app/models/user.rb) `create_personal_organization`) — this is intentional, self-serve onboarding. Don't change this to an invite-only model.
- **Stock-per-location tracking**: `storage_locations` (self-referential zone tree: room/cabinet/shelf/bench/drawer/box) and `part_storages` (part × location quantity). `StockMovement` is the append-only ledger; creating one updates the corresponding `PartStorage.quantity` in a single atomic `UPDATE` (race-safe), and blocks overdraws unless `organization.allow_negative_stock`. Never write `PartStorage.quantity` directly — always go through a movement.
- **Purchase orders**: `Order` / `OrderLine` (supplier orders). Status flow `pending → shipped → received` via `Order#advance!`; `cancelled` sits outside that flow. Reaching `received` credits stock (`receive_into_stock!`) — once per order. A model validation enforces this: `received` and `cancelled` are terminal, and `received` is only reachable through `advance!`. `OrderLineAllocation` splits a line's received quantity across storage zones (empty = fall back to the part's first location; otherwise must sum to the line quantity).
- **Projects**: `Project` / `ProjectLine` hold an imported BOM (`BomParser`) matched against parts for availability checks, order generation, and builds. A part can appear on several lines, so every decision (buildable, build deduction, ordering shortfalls, importing into an order) goes through `Project#required_by_part` / `#shortfall_by_part`, never per-line `ProjectLine#shortfall`.
- **Reordering** (alerts, project shortfalls) subtracts what's already on open orders (`Order.incoming_quantities`, pending + shipped), so repeat clicks don't double-order.
- **Generated references** (`Order.next_reference`, `Project.next_reference`) must be saved with `save_with_generated_reference! { … }` (`GeneratedReference` concern), which redraws on a concurrent clash instead of 500ing.
- **Attachments** go through `AttachmentValidation` (`validates_attachment :name, content_types:, max_size:`); add a limit for any new `has_one_attached` / `has_many_attached`. Files are served only to members of the owning organization by `StoredFilesController`: link them with `stored_file_path_for(attachment)`, never `rails_blob_path`/`url_for` — every `/rails/active_storage/*` route is shadowed with a 404 in `config/routes.rb`, and orphan blobs are purged daily (`PurgeUnattachedBlobsJob`). A new attachable model must expose `organization_id` (or be `Organization`) for `StoredFilesController#readable?`.
- **CSV imports** go through `BomParser.each_row`, which accepts UTF-8 (with or without BOM) and Windows-1252 (French Excel's default).
- **Order line splits**: changing an `OrderLine`'s quantity drops its `OrderLineAllocation` split (`after_update` callback), and `receive_into_stock!` credits any unsplit remainder to the fallback location.
- **Supplier catalogs**: `SupplierCatalog` (Mouser, DigiKey) for part lookup, order import, and Mouser cart push. API keys and DigiKey OAuth tokens are stored encrypted on `Organization`. Remote asset downloads go through `SupplierCatalog::RemoteFile` (SSRF-guarded) — don't fetch supplier URLs any other way.
- **Vite gems and npm plugin move together**: `vite_ruby` checks the npm `vite-plugin-ruby` version at boot and refuses to start on a mismatch, so bump them in one change (and run the system tests). `rack-proxy` is only used by the Vite dev-server proxy in development.
- **Active Storage** is installed so `.destroy` on `Organization`, `Part`, `Footprint`, and `Supplier` (all declare attachments) works correctly.

## Testing
- **Every model, controller, and non-trivial piece of business logic must have tests.** When you add or change a model validation, scope, callback, or method — or a controller action — add or update the corresponding test in `test/` in the same change. Don't treat tests as optional or a follow-up; a feature isn't done until it's tested.
- Framework: Minitest 6 + fixtures (`test/test_helper.rb`), not RSpec. Shared factory-style helpers (`create_organization`, `create_part`, `create_order`, etc.) live in `test/test_helper.rb` — prefer them over hand-rolling setup. Minitest 6 has no bundled `minitest/mock`; use the `stub_singleton` helper.
- Run the suite with `bin/rails test` (add `test:system` for system tests) before considering work complete.
- In the test env Vite runs with `autoBuild: true` into `public/vite-test/`. The stalled/failed runs seen on 2026-10-07 came from parallel workers racing to rebuild a stale bundle (fixed: see the prebuild in `test_helper.rb`). Still wrap manual runs in a `timeout`, use `PARALLEL_WORKERS=1` to isolate a single file, and kill stray processes by PID rather than `pkill -f`.
- `test/system/scanner_camera_test.rb` can be flaky when the whole system suite runs (fake camera timing); rerun it alone before treating a failure as real.
- `test_helper.rb` builds the frontend once before parallel workers fork (they used to race rebuilding a stale bundle). Don't run `db:seed:replant` against the test DB before tests: the seeds collide with fixtures — `bin/rails db:test:prepare` resets it.
- Tests share `storage/test.sqlite3`: don't run two `bin/rails test` processes at once (`SQLite3::BusyException`).

## Design reference
`design-makerstorage/` (not committed — it may be absent from a given checkout; ask for it rather than guessing) contains high-fidelity static HTML prototypes (not production code) covering the full intended app: dashboard, inventory table, component detail, storage zones tree, scanner, movements ledger, suppliers, alerts, members/roles, settings. See `design-makerstorage/README.md` for the full breakdown, design tokens, and interaction notes. Reimplement designs using the existing shadcn component set rather than recreating the prototypes' raw inline styles.

## Commit convention
`type(scope): description` — see `CONTRIBUTING.md` for full type/scope list. Lowercase, imperative mood, no trailing period, no `Co-Authored-By` trailer.

## Claude skills
Project skills live in `.claude/skills/<name>/SKILL.md` (no more `.claude/commands/`). `.claude/settings.local.json` and `.claude/*.lock` are per-machine and gitignored.

User-invoked workflows:
- `/commit` — propose a Conventional Commits message, run checks via `ci`, commit after confirmation, suggest a tag via `release`.
- `/merge [target]` — check readiness, run the full `ci` suite, merge into `main` (or `target`), optionally tag; never pushes without explicit approval.
- `/release [version]` — single source of truth for SemVer/tag rules (used by `/commit` and `/merge`).
- `/new-resource <name> [fields…]` — scaffold an org-scoped resource end to end (migration → model → controller → shadcn page → tests), modelled on Tags.
- `/design-to-page <screen>` — rebuild a `design-makerstorage/` prototype screen with shadcn components and English copy.

Also auto-loaded by Claude when relevant:
- `ci` — run the check suite sequentially with timeouts, Vite-hang aware (`/ci quick` for changed files only).
- `tenancy-review` — org scoping, role gates, FK `dependent:` rules, isolation tests.
- `stock-ledger` — stock/order invariants and required tests (ledger-only stock changes, receive-once orders).
- `supplier-api` — Mouser/DigiKey integration, OAuth, encrypted credentials, SSRF-safe downloads.

## Commands
- Dev server: `bin/dev` (runs Rails + Vite via `Procfile.dev`)
- Lint: `bin/rubocop`
- Security: `bin/brakeman`, `bin/bundler-audit`
- Type check: `npm run check`
- Tests: `bin/rails test` (`bin/rails test:system` for system tests) — also run via `bin/ci` (defined in `config/ci.rb`) alongside lint/security
