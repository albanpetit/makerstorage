---
name: new-resource
description: Scaffold a new organization-scoped resource in Makerstorage end to end — migration, model, controller, routes, Inertia/React page built from shadcn components, sidebar entry, and tests — following the project's conventions, using Tags as the reference implementation.
argument-hint: "<resource-name> [fields…]"
disable-model-invocation: true
---

Create the resource described by `$ARGUMENTS` (e.g. `tools name:string serial:string location:references`). If the fields, relations, or which roles may write are unclear, ask before generating anything.

**Reference implementation** — read these first and mirror their structure, naming, and comment style:
`db/migrate/*_create_tags.rb`, `app/models/tag.rb`, `app/controllers/tags_controller.rb`, `app/frontend/pages/tags/index.tsx`, `test/models/tag_test.rb`, `test/controllers/tags_controller_test.rb`.

Don't use `bin/rails generate scaffold` — it produces ERB views and a controller shape this app doesn't use. Write the files by hand (a plain `bin/rails generate migration` for the timestamped filename is fine).

## 1. Migration

```ruby
create_table :things do |t|
  t.references :organization, null: false, foreign_key: true
  t.string :name, null: false
  # t.references :storage_location, foreign_key: true   # every relation gets an FK
  t.timestamps
end
add_index :things, [ :organization_id, :name ], unique: true   # if names are unique per org
```
Run `bin/rails db:migrate` and check `db/schema.rb` changed as expected.

## 2. Model

- `belongs_to :organization` + other `belongs_to`; sections commented `# Associations`, `# Validations`, `# Scopes`, `# Methods` like the existing models.
- Validations scoped per org (`uniqueness: { scope: :organization_id }`), and a same-org validation for every association to another org-owned record.
- `scope :alphabetical, -> { order(:name) }` if the UI lists it.
- **Parents**: add `has_many :things, dependent: :destroy` to `Organization`, and the matching `has_many … dependent:` on every model this table references (`:restrict_with_error` if deleting the parent should be blocked). See the `tenancy-review` skill §4.

## 3. Controller + routes

- `resources :things, only: %i[index create update destroy]` in `config/routes.rb` (add `show`/member routes only if needed).
- Controller skeleton = `TagsController`: `include Auth`; `verify_organization_access`; `verify_organization_writer` on every mutating action; `set_thing` via `current_organization.things.find`; strong params `params.require(:thing).permit(...)`; a private `serialize_thing` returning a plain hash; `render inertia: "things/index", props: {...}`.
- Success → `redirect_to things_path, notice: "…"`. Failure → `redirect_back_or_to things_path, alert: "…", inertia: { errors: inertia_errors(thing, as: :thing) }`.
- Select options for other resources come from `OptionListSerializers` (`serialize_categories`, `serialize_storage_locations`, …).
- Avoid N+1 in `index` (counts via `left_joins … COUNT … group`, or `includes`).

## 4. Page (`app/frontend/pages/things/index.tsx`)

- Wrap in `<AppLayout header={<PageHeader title=… subtitle=…>…</PageHeader>}>`, show `<FlashMessages />` like the Tags page.
- Only `@/components/ui/*` building blocks: `Table`, `Card`, `Dialog` for create/edit, `AlertDialog` for delete confirmation, `Field`/`FieldLabel`/`FieldError` + `Input`/`Textarea`/`Select` for forms, `Badge`, `Button`, Lucide icons. No raw `<button>`/`<input>`/`<select>`, no inline styles.
- Forms: `useForm<{ thing: {...} }>` so errors arrive as `thing.name`; submit with `form.post('/things')` / `form.patch(...)`; delete with `router.delete(...)`.
- Hide write actions with `const { canWrite } = usePermissions()`.
- Typed props interface at the top of the file; English UI copy.
- Add the nav entry to the item list in `app/frontend/components/app-sidebar.tsx` (`{ title, url, icon }`, `adminOnly: true` if admin-only).

## 5. Tests (same change, not a follow-up)

- `test/models/thing_test.rb`: validations, uniqueness per org (same name allowed in another org), same-org validation, scopes, dependent behaviour on destroy.
- `test/controllers/things_controller_test.rb`, mirroring `TagsControllerTest`: signed-out redirect; index serializes via `inertia_props`; **index doesn't leak another org's records**; create scopes to the current org; update/destroy; invalid input returns errors; can't touch another org's record (404).
- Add a viewer case to `test/controllers/role_authorization_test.rb`.
- Add a `create_thing(organization:, **attrs)` factory to `test/test_helper.rb` next to the others.

## 6. Finish

Run `/ci quick` (or at least the two new test files + `bin/rubocop` + `npm run check`), apply the `tenancy-review` checklist to the result, then summarize the files created.
