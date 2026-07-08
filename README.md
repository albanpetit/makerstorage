# Makerstorage

[![CI](https://github.com/albanpetit/partstable/actions/workflows/ci.yml/badge.svg)](https://github.com/albanpetit/partstable/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-3.4.8-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1-CC0000?logo=rubyonrails&logoColor=white)
![React](https://img.shields.io/badge/React-19-149ECA?logo=react&logoColor=white)

Electronics-parts inventory manager for makerspaces and fablabs. Track components, categories, footprints, storage zones, stock movements, suppliers, and low-stock alerts — all scoped per organization.

## Features

- **Inventory** — parts with SKU/MPN/barcode, categories, footprints, tags, datasheets and images
- **Stock tracking** — quantities per storage location, with a full stock-movement ledger
- **Storage zones** — hierarchical locations (room → cabinet → shelf → bench → drawer → box)
- **Suppliers & purchasing** — preferred suppliers, pricing, lead times, purchase orders
- **Low-stock alerts** — automatic reorder suggestions from configurable thresholds
- **Multi-tenant** — every organization has isolated data and its own members with roles (owner/admin/member/viewer)
- **CSV import** — bulk-load parts into an organization

## Tech stack

| Layer      | Tools                                                              |
| ---------- | ------------------------------------------------------------------ |
| Backend    | Rails 8.1, SQLite, Devise, Inertia Rails, Solid Queue/Cache/Cable  |
| Frontend   | Inertia.js, React 19, TypeScript, Vite, Tailwind CSS v4, shadcn/ui |
| Deployment | Kamal                                                              |

## Getting started

### Using the dev container (recommended)

Open the project in VS Code and reopen in the container (`.devcontainer/`) — Ruby, Node, and SQLite come preinstalled. Then run:

```bash
bin/setup
```

### Manual setup

Requires Ruby 3.4.8 and Node 24+.

```bash
bundle install
npm install
bin/rails db:prepare
bin/dev   # starts Rails + Vite (see Procfile.dev)
```

The app is served at `http://localhost:3000`.

## Quality checks

```bash
bin/rails test          # unit & controller tests
bin/rails test:system   # system tests (Capybara)
bin/rubocop              # Ruby style
bin/brakeman             # security static analysis
bin/bundler-audit        # known gem CVEs
npm run check            # TypeScript type check
```

Run everything at once with `bin/ci`.

## Commit convention

To keep a clear, readable, and consistent git history, all commit messages follow:

```text
type(scope): description
```

### Type

| Type       | Meaning                                             |
| ---------- | --------------------------------------------------- |
| `feat`     | New feature                                         |
| `fix`      | Bug fix                                             |
| `style`    | Formatting, naming, or UI tweaks (no logic change)  |
| `refactor` | Code refactoring without adding or fixing behavior  |
| `perf`     | Performance improvements                            |
| `test`     | Adding or updating tests                            |
| `build`    | Build system or tooling changes (Vite, Tailwind…)   |
| `deps`     | Dependency updates                                  |
| `ci`       | Continuous integration changes                      |
| `chore`    | Other changes that don't modify the product         |
| `docs`     | Documentation only                                  |

### Scope

**Backend:** `api` (controllers/business logic) · `db` (migrations/schema) · `model` (ActiveRecord) · `auth` (authentication) · `policy` (authorization)

**Frontend:** `page` (Inertia pages) · `ui` (React components) · `state` (state management) · `types` (TypeScript types) · `style` (Tailwind/CSS)

**Tooling:** `vite` · `build` · `infra` (Node/env/Docker) · `repo` (repo structure/scripts)

### Description

Short and imperative, no trailing period, English or French (stay consistent within a commit).

### Examples

```text
feat(db): add organizations table
feat(model): add polymorphic owner to components
fix(api): prevent negative component quantity
ui(component): improve stock table layout
types(stock): add component interfaces
build(vite): fix esbuild resolution issue
deps: update inertia and react versions
docs(repo): add commit convention
```
