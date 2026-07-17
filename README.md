# Makerstorage

[![test](https://github.com/albanpetit/partstable/actions/workflows/test.yml/badge.svg)](https://github.com/albanpetit/partstable/actions/workflows/ci.yml)
![Ruby](https://img.shields.io/badge/Ruby-3.4.8-CC342D?logo=ruby&logoColor=white)
![Rails](https://img.shields.io/badge/Rails-8.1-CC0000?logo=rubyonrails&logoColor=white)
![React](https://img.shields.io/badge/React-19-149ECA?logo=react&logoColor=white)

A multi-tenant inventory manager for makerspaces and fablabs, purpose-built for electronic components. Catalog parts, keep stock accurate down to the drawer, reorder before you run out all scoped per organization.

![Makerstorage dashboard](.github/assets/makerstorage.png)

## Features

- **Inventory** — parts with SKU / MPN / barcode, manufacturer, technical specs, and per-supplier pricing
- **Classification** — organize parts with hierarchical categories, reusable footprints, and free-form tags, each managed from its own page
- **Stock tracking** — quantities per storage location, backed by an append-only stock-movement ledger
- **Storage zones** — a hierarchical location tree (room → cabinet → shelf → bench → drawer → box)
- **Barcode scanner** — look up parts and record stock movements straight from a scan
- **Suppliers & purchasing** — preferred suppliers, pricing, lead times, and generated purchase orders
- **Low-stock alerts** — automatic reorder suggestions from configurable per-part thresholds
- **Dashboard** — at-a-glance stock value, low-stock counts, and category breakdowns
- **Multi-tenant** — every organization has isolated data, its own members with roles (owner / admin / member / viewer), and a configurable internal part-number (IPN) scheme
- **CSV import** — bulk-load parts, auto-creating categories and locations as needed

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

## Running with Docker

The app ships as a self-contained production image (Rails behind Thruster on port
80, using SQLite and local file storage). To run your own instance:

```bash
# Build the image
docker build -t makerstorage .

# Run it
docker run -d --name makerstorage \
  -p 80:80 \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -v makerstorage-storage:/rails/storage \
  makerstorage
```

- **`RAILS_MASTER_KEY`** decrypts `config/credentials.yml.enc` — use your own key.
- The **`makerstorage-storage` volume** holds the SQLite databases and uploaded
  files; it persists across restarts and is what you back up.
- The container runs database migrations on boot and serves a health check at
  **`GET /up`**.
- Map the port however you like (e.g. `-p 3000:80`) and put a TLS-terminating
  reverse proxy in front of it for production.

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

## Contributing

Commit conventions, the local check suite, and other contributor guidelines live in [CONTRIBUTING.md](CONTRIBUTING.md).
