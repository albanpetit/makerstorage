---
name: design-to-page
description: Implement or align a Makerstorage screen with its high-fidelity prototype in design-makerstorage/, rebuilt with the existing shadcn/ui components and English copy rather than the prototype's inline styles and French text.
argument-hint: "<screen> (e.g. dashboard, inventory, storage-zones, scanner, alerts)"
disable-model-invocation: true
---

Bring the screen named in `$ARGUMENTS` in line with its prototype.

## 0. Locate the prototype

The prototypes live in `design-makerstorage/` (gitignored historically, so it may only exist on some machines). If the directory is missing, **stop and ask the user where it is** — don't guess the design from memory. Then read `design-makerstorage/README.md` (screen list, design tokens, interaction notes) and the HTML file for the requested screen.

## 1. Map before building

Produce a short mapping and show it to the user before writing code:
- **Layout regions** of the prototype → existing building blocks: `AppLayout`, `PageHeader`, `Card`, `Table`, `Sheet` (side panels such as part detail), `Dialog`/`AlertDialog`, `Badge`, `Tooltip`, `DropdownMenu`, `Combobox`, `ScrollArea`, `Skeleton`, `Sidebar` (all in `app/frontend/components/ui/`), plus app components (`storage-zone-tree-picker`, `category-select`, `tag-picker`, `part-detail-sheet`, `global-search`).
- **Data** each region needs → which controller props already provide it, and what must be added to the controller serializer (with a test).
- **Gaps**: anything no existing component covers. Prefer composing existing ones; propose adding a shadcn component (`npx shadcn@latest add <name>`, already allowed) only when nothing fits. Never edit files under `components/ui/` to match a pixel.

## 2. Build rules

- Colors, radii, spacing come from the Tailwind/shadcn theme tokens (`bg-muted`, `text-muted-foreground`, `border`, `rounded-md`…), not hex values or `style={{…}}` copied from the prototype. If a prototype token has no theme equivalent, point it out rather than hard-coding it.
- **Copy is English.** Translate the prototype's French labels to concise English UI text; keep terminology consistent with existing pages (e.g. "Storage Zones", "Movements", "Inventory").
- Respect permissions: hide write actions with `usePermissions()` (`canWrite`, `canAdminister`).
- Responsive: the prototypes target desktop; make sure the page still works at phone width (the app is used on the shop floor with the scanner).
- Keep page files manageable — if the page grows past ~500 lines, extract sections into `app/frontend/components/<feature>/…`.

## 3. Verify

- `npm run check` for types (wrap in `timeout 300`; see the `ci` skill for the known hang).
- Run the app (`bin/dev`) and compare against the prototype screen by screen; list remaining deliberate differences (interaction not yet backed by data, etc.).
- If the controller changed, its tests change in the same commit.
