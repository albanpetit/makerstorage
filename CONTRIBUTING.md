# Contributing

Thanks for contributing to Makerstorage! This guide covers the conventions we follow so the codebase and its history stay clean and readable.

## Before you push

Run the full check suite locally — it mirrors CI:

```bash
bin/ci
```

Or run the pieces individually:

```bash
bin/rails test          # unit & controller tests
bin/rails test:system   # system tests (Capybara)
bin/rubocop             # Ruby style
bin/brakeman            # security static analysis
bin/bundler-audit       # known gem CVEs
npm run check           # TypeScript type check
```

Every model, controller, and non-trivial piece of business logic must ship with tests in the same change.

## Commit convention

To keep a clear, readable, and consistent git history, all commit messages follow:

```text
type(scope): description
```

### Type

| Type       | Meaning                                            |
| ---------- | -------------------------------------------------- |
| `feat`     | New feature                                        |
| `fix`      | Bug fix                                            |
| `style`    | Formatting, naming, or UI tweaks (no logic change) |
| `refactor` | Code refactoring without adding or fixing behavior |
| `perf`     | Performance improvements                           |
| `test`     | Adding or updating tests                           |
| `build`    | Build system or tooling changes (Vite, Tailwind…)  |
| `deps`     | Dependency updates                                 |
| `ci`       | Continuous integration changes                     |
| `chore`    | Other changes that don't modify the product        |
| `docs`     | Documentation only                                 |

### Scope

**Backend:** `api` (controllers/business logic) · `db` (migrations/schema) · `model` (ActiveRecord) · `auth` (authentication) · `policy` (authorization)

**Frontend:** `page` (Inertia pages) · `ui` (React components) · `state` (state management) · `types` (TypeScript types) · `style` (Tailwind/CSS)

**Tooling:** `vite` · `build` · `infra` (Node/env/Docker) · `repo` (repo structure/scripts)

Combine multiple scopes with a space when a change spans several — e.g. `feat(api ui): …`.

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
