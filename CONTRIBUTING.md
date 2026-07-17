# Contributing

Thanks for contributing to Makerstorage! This guide covers the conventions we follow so the codebase and its history stay clean and readable.

## Development setup

### Dev container (recommended)

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
```

Start the dev server (Rails + Vite, via `Procfile.dev`):

```bash
bin/dev
```

The dev server is served at `http://localhost:3000`.

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

## Branching

We follow a **trunk-based** flow with short-lived branches — no long-lived `dev`/`develop` branch.

- `main` is the single source of truth and must stay **releasable at all times**: green CI, and every version tag is cut from it.
- For any non-trivial change, branch off the latest `main`, open a pull request, let CI run, then merge back and delete the branch:

  ```bash
  git checkout main && git pull
  git checkout -b feat/supplier-import
  # …work, commit…
  git push -u origin feat/supplier-import   # then open a PR
  ```

- **Trivial changes** (a typo, a one-line fix, a doc tweak) can go straight to `main` — don't impose PR ceremony where it adds no value. Rule of thumb: branch when the change is big enough that you'd want CI to vet it before it becomes permanent.

### Branch names

Use the commit **type** as the prefix, then a short kebab-case description:

```text
feat/supplier-import
fix/negative-stock-overdraw
refactor/storage-tree-query
docs/branching-convention
```

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

## Releases & versioning

Releases follow [Semantic Versioning](https://semver.org/): `vMAJOR.MINOR.PATCH`. While the app is pre-stable we stay on the `0.x` line, where a breaking change bumps **MINOR** rather than MAJOR.

- **PATCH** (`v0.3.1` → `v0.3.2`) — only `fix`/`perf` commits since the last tag.
- **MINOR** (`v0.3.1` → `v0.4.0`) — any `feat` (or, on `0.x`, a breaking change) since the last tag.
- **MAJOR** — reserved for the first stable `v1.0.0` and breaking changes thereafter.

Tags are annotated and cut from `main` once CI is green. Pushing the tag is all that's
needed — the [`Release`](.github/workflows/release.yml) workflow wraps it in a GitHub
Release with generated notes, and the [`Deploy to Production`](.github/workflows/deploy.yml)
workflow ships it:

```bash
git checkout main && git pull
git tag -a v0.4.0 -m "v0.4.0"
git push origin v0.4.0   # → creates the GitHub Release and deploys to production
```

The `/commit` command will suggest a version bump and print these commands when a commit is a good moment to release — it never tags automatically.

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