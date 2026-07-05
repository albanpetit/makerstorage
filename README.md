# Makerstorage

## Commit Convention

To keep a clear, readable, and consistent git history, all commit messages must follow this convention:

type(scope): description

---

### 1. Type

The **type** describes the nature of the change:

- **feat** → New feature
- **fix** → Bug fix
- **style** → Formatting, naming, or UI tweaks (no logic change)
- **refactor** → Code refactoring without adding or fixing functionality
- **perf** → Performance improvements
- **test** → Adding or updating tests
- **build** → Build system or tooling changes (Vite, Tailwind, etc.)
- **deps** → Dependency updates
- **ci** → Continuous integration changes
- **chore** → Other changes that do not modify the product itself
- **docs** → Documentation only

---

### 2. Scope

The **scope** specifies the area of the application affected by the commit.

#### Backend (Ruby on Rails)
- **api** → Controllers, services, business logic
- **db** → Migrations, schema changes
- **model** → ActiveRecord models
- **auth** → Authentication and authorization
- **policy** → Permissions and access control

#### Frontend (Inertia + React + TypeScript)
- **page** → Inertia pages
- **ui** → React components
- **state** → State management
- **types** → TypeScript types and interfaces
- **style** → Tailwind / CSS styling

#### Tooling / Stack
- **vite** → Vite configuration
- **build** → Build pipeline
- **infra** → Node, environment, Docker, etc.
- **repo** → Repository structure, scripts, config

---

### 3. Description

- Must be **short and imperative**
- Do **not** end with a period
- Use **English or French**, but stay consistent across the project

Examples:
- `add organization stock support`
- `fix component quantity validation`
- `simplify stock table rendering`

---

### Examples

feat(db): add organizations table
feat(model): add polymorphic owner to components
feat(stock): allow organization-owned stock
fix(api): prevent negative component quantity
ui(component): improve stock table layout
types(stock): add component interfaces
build(vite): fix esbuild resolution issue
deps: update inertia and react versions
docs(repo): add commit convention

---

👉 This convention keeps commits easy to read and filter, while staying lightweight and adapted to a Rails + Inertia + React + TypeScript stack.
