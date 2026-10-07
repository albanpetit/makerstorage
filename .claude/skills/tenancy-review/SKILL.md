---
name: tenancy-review
description: Multi-tenancy and authorization checklist for Makerstorage. Use whenever you add or change a controller action, model association, migration with a foreign key, or role/membership logic — and when reviewing a diff for security — to make sure every query is scoped to current_organization, every mutation is role-gated, every FK has a dependent rule, and viewers/inactive members can't write.
---

Makerstorage is multi-tenant: one database, every domain row carries `organization_id`, and the only thing standing between two makerspaces' data is that every query goes through `current_organization`. Apply this checklist to the code you're writing or the diff you're reviewing. Report each item as OK / issue (with `file:line`) / not applicable.

## 1. Every lookup goes through the tenant

- Records are loaded as `current_organization.<things>.find(params[:id])` (or `find_by`), never `Thing.find`, `Thing.where(id: params[...])`, or `Thing.find_by(...)` without the org scope.
- IDs coming from params for *associated* records are re-resolved through the org too: e.g. `current_organization.storage_locations.find_by(id: params[:storage_location_id])`, `current_organization.parts.find_by(id: raw[:part_id])`. A foreign ID silently accepted into a `create`/`update` is a cross-tenant write.
- Nested resources: load the parent through the org, then the child through the parent (`@order = current_organization.orders.find(params[:order_id]); @order.order_lines.find(params[:id])`).
- Models that join two org-owned records validate both sides belong to the same org (see `StockMovement#storage_location_must_belong_to_same_organization`, `Order#supplier_must_belong_to_same_organization`, `OrderLineAllocation`). Add the same kind of validation to any new join model.
- Grep the diff: `git diff main... | grep -nE '^\+.*\b[A-Z][A-Za-z]+\.(find|find_by|where)\('` — every hit needs a justification.

## 2. Every action is role-gated

Controllers `include Auth` and declare, in this order:
```ruby
before_action :verify_organization_access
before_action :verify_organization_writer, only: %i[create update destroy ...]   # blocks viewers
before_action :verify_organization_admin,  only: %i[...]                          # settings, bulk destroy, integrations
```
- Every new **mutating** action (including custom member/collection routes like `advance`, `import`, `bulk_*`, `move_stock`) must appear in a writer/admin/owner `only:` list. A new action missing from that list is open to viewers.
- Role hierarchy: `owner` > `admin` > `member` > `viewer`. Only an owner can grant/revoke the owner role or remove an owner (`MembersController#verify_owner_role_authority` / `verify_owner_removal_authority`). An org must always keep ≥ 1 active owner.
- Frontend mirrors the gate with `usePermissions()` (`canWrite`, `canAdminister`, `isOwner`) to hide actions — this is cosmetic only; the controller gate is what counts.
- Tests: add a viewer case to `test/controllers/role_authorization_test.rb` (pattern: `act_as @viewer`, assert no record created and redirect) for every new mutating action.

## 3. Membership `active` flag

`OrganizationMembership` has an `active` boolean. Only active memberships grant access: `user.organizations` goes through `active_organization_memberships`, and so do `User#member_of_organization?`, `#writer_of?`, `#admin_of?`, `#owner_of?`, `#role_in`. Any new membership check must do the same (never `user.organization_memberships.exists?` for access), and come with a test proving a deactivated member is denied (see `RoleAuthorizationTest`).

## 4. Foreign keys always have a dependent rule

SQLite enforces FKs, so a parent `.destroy` with a referencing child raises `ActiveRecord::InvalidForeignKey` (HTTP 500) unless the parent model declares the association.
- For every `t.references …, foreign_key: true` / `add_foreign_key` in a migration, the parent model needs `has_many :children, dependent: …`:
  - `:restrict_with_error` for history/ledger/order data (stock movements, order lines, project lines) — the controller then shows `errors.full_messages`.
  - `:destroy` for owned detail rows (part_storages, part_tags, allocations of a still-open order).
- Also add the new association to `Organization` (`has_many …, dependent: :destroy`) if the table carries `organization_id`, so deleting an org cascades. **Order matters**: `Organization`'s dependents are destroyed in declaration order, so declare the new table *before* anything it references with `restrict_with_error` (otherwise `org.destroy` silently returns false). `OrganizationTest#"destroy removes a populated organization…"` guards this — extend it with a row of the new table.
- Test: destroying a parent that still has children either succeeds or returns a flash error — never raises.

## 5. Tests that prove isolation

For each new index/show-style action, a test like `TagsControllerTest#"index does not leak another organization's tags"`: create a record in `create_organization` (another org), sign in as a user of their own org, assert it's absent from `inertia_props` / returns 404 on direct access.

## Output

A short checklist with findings ranked by severity (cross-tenant read/write > missing role gate > FK 500 > missing test). Offer to fix; don't silently rewrite unrelated code.
