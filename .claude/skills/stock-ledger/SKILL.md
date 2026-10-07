---
name: stock-ledger
description: Invariants and required tests for anything that changes stock quantities in Makerstorage — StockMovement, PartStorage, Order#advance!/receive_into_stock!, OrderLineAllocation, storage_locations#move_stock, parts#bulk_move, scans#create_movement, project builds. Use before editing or reviewing any of that code, or when adding a feature that adds/removes/moves stock or changes an order's status.
---

Stock is the core asset of the app; a bug here silently corrupts inventory counts. Read the relevant code first (`app/models/stock_movement.rb`, `app/models/order.rb`, and the controller you're touching), then hold to these rules.

## Invariants

1. **The ledger is the only way to change stock.** `StockMovement` is append-only; creating one applies its `quantity_delta` to `PartStorage.quantity` in its `before_create :apply_to_part_storage` callback. Never `update`/`update_column`/`update_all` `PartStorage.quantity` directly, never `update`/`destroy` an existing movement. Corrections are new `adjustment` movements.
2. **Movement types and signs**: `in` → delta > 0, `out` → delta < 0, `adjustment` → any non-zero. A move between zones is *two* movements (`out` from source, `in` to destination) in one transaction (see `StorageLocationsController#move_stock`).
3. **Overdraw guard is atomic.** The negative-stock check lives in the `UPDATE … WHERE quantity + delta >= 0` statement (race-safe); the validation `resulting_quantity_cannot_be_negative` is only an advisory early error. Keep both; don't replace the atomic update with read-then-write. `organization.allow_negative_stock` disables the guard.
4. **Multi-movement operations are all-or-nothing.** Wrap them in `ActiveRecord::Base.transaction` and roll back on the first failure (`raise ActiveRecord::Rollback` or use `create!`).
5. **Every movement is attributed**: `organization`, `part`, `storage_location` (same org), `user: current_user`, and a human `reason`/`reference` (e.g. `"Received #{order.reference}"`, `"Moved to #{to.name}"`).

## Order lifecycle (credits stock exactly once)

- Statuses: `pending → shipped → received` via `Order#advance!` (row-locked). `cancelled` is terminal and outside that sequence.
- Reaching `received` calls `receive_into_stock!`: per line, one `in` movement per `OrderLineAllocation`, or the whole quantity to `part.storage_locations.first` when the line has no allocations; lines with neither are returned as `skipped`, never silently dropped.
- Allocations: empty, or summing **exactly** to `line.quantity`. Changing a line's quantity must clear or rebalance its split. Only editable (`pending`/`shipped`) orders may change lines or allocations.
- **A received or cancelled order must never move again.** Enforced by `Order#status_transition_must_be_allowed` (terminal statuses; `received` only via `advance!`, which sets `@advancing`) and by `advance!` refusing any status outside `ADVANCE_SEQUENCE`. Don't bypass it with `update_column`/`update_all` on `status`; keep the regression tests in `test/models/order_test.rb` passing (cancelled can't advance, received can't be re-opened).

## Required tests for any change here

Use the `test/test_helper.rb` factories (`create_organization`, `create_part`, `create_storage_location`, `create_order`, …) and assert on `PartStorage.find_by(part:, storage_location:).quantity` and `StockMovement.count`:
- the happy path changes stock by exactly the expected amount;
- an overdraw is rejected (and accepted when `allow_negative_stock`), leaving quantity and movement count unchanged;
- a multi-step operation that fails halfway leaves **no** movements behind;
- for orders: advancing a `received` or `cancelled` order changes nothing; receiving twice is impossible; allocations split into the right zones; unlocated lines are reported in `skipped`;
- cross-org: a storage location or part from another organization is rejected.

Then run the related test files (`/ci quick`) before calling the change done.
