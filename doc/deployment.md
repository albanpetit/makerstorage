# Deployment

Makerstorage deploys to a self-hosted Docker server with [Kamal](https://kamal-deploy.org)
(2.x). The server is the same arm64 host that runs other apps, fronted by a
**Cloudflare Tunnel** (which also terminates TLS) and managed with **Portainer**.

## How it ships

Deploys are **tag-triggered** (continuous delivery), matching the release flow in
[CONTRIBUTING.md](../CONTRIBUTING.md#releases--versioning):

```bash
git checkout main && git pull      # main must be green
git tag -a v0.4.0 -m "v0.4.0"
git push origin v0.4.0             # ← this fires .github/workflows/deploy.yml
```

The [`Deploy to Production`](../.github/workflows/deploy.yml) workflow then:

1. builds the Docker image for **arm64** (via QEMU on the amd64 runner),
2. pushes it to `ghcr.io/albanpetit/makerstorage`,
3. SSHes to the server **through the Cloudflare Tunnel** (`cloudflared access ssh`),
4. runs `kamal deploy` — pull, boot the new container, register it with the shared
   `kamal-proxy`, health-check `/up`, then retire the old container.

You can also re-deploy the current `main` manually from the Actions tab
(**Run workflow** → uses `workflow_dispatch`).

## Required GitHub secrets

Set these under **Settings → Secrets and variables → Actions**:

| Secret | Purpose |
| ------ | ------- |
| `SSH_PRIVATE_KEY` | Private key (ed25519) authorized on the deploy user; used by Kamal's SSH. |
| `DEPLOY_HOST` | Hostname of the server as reached over the Cloudflare Tunnel (the `cloudflared` SSH hostname). |
| `DEPLOY_USER` | SSH user on the server (e.g. `deploy`). |
| `APP_HOST` | Public hostname Makerstorage is served on (the Kamal proxy host, e.g. `makerstorage.example.com`). |
| `RAILS_MASTER_KEY` | Contents of `config/master.key` — decrypts Rails credentials in production. |

> If the Cloudflare Tunnel's SSH route is ever put behind a **Cloudflare Access**
> policy, `cloudflared` will additionally need a service token — add
> `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` secrets and pass them as env in
> the deploy and backup steps. It isn't required today (the route is unauthenticated,
> same as the paperflux setup).

`GITHUB_TOKEN` is provided automatically by Actions and is used both to push the
image to ghcr.io and (via [`.kamal/secrets`](../.kamal/secrets)) as the registry
password on the server.

## Portainer stack grouping

Kamal runs containers with `docker run` rather than Docker Compose, so by default
they'd appear as loose containers in Portainer. `config/deploy.yml` adds
`com.docker.compose.project=makerstorage` labels, which Portainer treats as an
(external) stack — so the app shows up grouped under **makerstorage** with its
container(s) nested inside. The shared `kamal-proxy` container stays separate, as
it fronts every app on the host.

## First deploy

The host is already provisioned (Docker + `kamal-proxy` are running for the other
apps), so a tag push should just work. If this is ever the very first Kamal app on
a fresh host, run `bin/kamal setup` once from a machine with the secrets exported.

## Deploying / debugging from a dev machine

With the same secrets exported (or `config/master.key` present locally and a ghcr
PAT via the `gh` CLI), the Kamal aliases work directly:

```bash
DEPLOY_HOST=… DEPLOY_USER=… APP_HOST=… \
  bin/kamal deploy       # or: logs · console · shell · dbc
```

## Backups

The app runs on **SQLite**, and Active Storage uploads use the local **Disk**
service — so the entire dataset (four `*.sqlite3` files **and** every uploaded blob)
lives in the one `makerstorage` Docker volume mounted at `/rails/storage`. That
volume *is* the database; losing it loses everything, so it is backed up off-host.

- [`bin/backup-storage`](../bin/backup-storage) produces a consistent snapshot: each
  SQLite database is copied with the online `.backup` API (safe while the app is
  writing, WAL-aware — a plain `cp` of a live WAL file can be unrestorable), and the
  Active Storage blob directories are added alongside. It streams a `.tar.gz` to
  stdout, or writes rotated archives to a directory with `--out DIR`.
- The [`Backup`](../.github/workflows/backup.yml) workflow runs nightly (03:17 UTC,
  plus manual dispatch): it SSHes in over the Cloudflare Tunnel, runs the script
  inside the running container, streams the archive back, verifies it, and stores it
  as a **workflow artifact** (30-day retention) — a copy that survives loss of the
  server or volume. It reuses the deploy secrets; no new ones are required.

### Restore

```bash
# 1. Get an archive: download it from the Backup workflow run's artifacts, or from
#    an on-host --out directory. Then copy it to the server and unpack:
tar -xzf makerstorage-<stamp>.tar.gz          # → db/  files/

# 2. Stop the app so nothing is writing to the volume.
bin/kamal app stop

# 3. Replace the volume contents. `db/` holds the databases, `files/` the blobs.
#    (Adjust the volume mountpoint via `docker volume inspect makerstorage`.)
docker run --rm -v makerstorage:/dst -v "$PWD:/src" alpine sh -c '
  rm -f /dst/*.sqlite3 /dst/*.sqlite3-wal /dst/*.sqlite3-shm
  cp /src/db/*.sqlite3 /dst/
  cp -a /src/files/. /dst/'

# 4. Bring it back up and confirm health.
bin/kamal app boot
bin/kamal app exec 'bin/rails runner "puts ActiveRecord::Base.connection.execute(%{PRAGMA integrity_check}).to_a.inspect"'
```

### Growing past artifacts

Workflow artifacts are a solid launch-night safety net, but they hold plaintext
customer data and cap at 90 days. As uploads grow, point the backup at object
storage instead — e.g. add an `rclone`/`aws s3 cp` step to the workflow targeting
Cloudflare R2 or S3, and/or switch Active Storage itself to an S3/R2 service in
[config/storage.yml](../config/storage.yml) (which also removes the single-host
constraint on uploads — see the note above about SQLite + local Disk tying the app
to one server).

## Optional hardening

Since Cloudflare terminates TLS and the Kamal proxy serves plain HTTP
(`proxy.ssl: false`), you may want to set `config.assume_ssl = true` in
[config/environments/production.rb](../config/environments/production.rb) so Rails
issues secure cookies. Leave `config.force_ssl` off (Cloudflare already forces
HTTPS at the edge) to avoid a redirect loop over the tunnel.
