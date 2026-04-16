# 321 — How to use

3... 2... 1... deploy! Your dashboard for managing Perl web services.

**Dashboard:** https://321.do.dev/ (dev) or https://321.do/ (prod)
**Login:** `321` / `kaizen`

---

## Adding a new service

### 1. Register it

Click **+ ADD SERVICE** on the dashboard. Fill in the name (`group.service`), repo path, and ports — the rest auto-fills. The page has a worked example and tips right alongside the form.

### 2. Add a manifest to your repo

Every service repo needs a `.321.yml` at the root:

```yaml
name: pizza.web
entry: bin/app.pl
runner: hypnotoad
```

Optional fields: `perl` (perlbrew version), `health` (probe path), `env_required`, `env_optional`. See the Add Service page for the full list.

### 3. Install it

```
321 install pizza.web
```

This clones the repo (if needed), installs Perl deps, sets up ubic + nginx + SSL, and starts the service.

### 4. Set secrets

If your manifest declares `env_required`, set them from the service detail page (click the service name on the dashboard). The **SECRETS** panel shows what's missing and lets you set values. Deploy is blocked until all required secrets are present.

### 5. Check it

Open the dashboard. Green light = running. Click **VISIT** to open the site.

---

## Updating a service

Four buttons on the service detail page:

- **DEPLOY** — pull code, deps, migrate, restart. Regular deployments.
- **UPDATE** — pull code, deps, migrate (no restart). Check everything before bouncing.
- **MIGRATE** — run `bin/migrate` only. Re-run a migration.
- **RESTART** — restart + verify port. After config/env changes.

All four show per-step output. Failed steps expand automatically.

**CLI equivalents:**
```
321 go pizza.web          # DEPLOY
321 update pizza.web      # UPDATE
321 migrate pizza.web     # MIGRATE
321 restart pizza.web     # RESTART
```

On dev, `321 go` skips the git pull — just restarts with your local changes.

---

## Migrations

Drop a `bin/migrate` script in your service repo. 321 runs it during DEPLOY and UPDATE, between deps and restart. Non-zero exit aborts before restart — a bad migration won't take down a running service.

Use whatever tool you like. 321 only cares about the exit code.

---

## Secrets

Managed from the service detail page or the API:

- **Dashboard badge** shows `secrets: N/M` per service
- **Service detail** has a SECRETS panel to set/delete keys
- Values stored in `secrets/<name>.env` (chmod 600, gitignored)
- Every change is audit-logged in `secrets/<name>.audit.log`
- Deploy is blocked if any `env_required` key is missing

---

## If something goes wrong

- **Deploy failed at `apt_deps`** — run the `sudo apt install ...` shown in the error
- **Deploy failed at `cpanm`** — usually a missing system lib. Add it to `apt_deps` in your service YAML
- **Deploy failed at `git_pull`** — check `branch:` matches the actual branch (main vs master)
- **Deploy blocked on secrets** — set the missing keys in the SECRETS panel
- **Service won't start** — check the **stderr** tab
- **Port already in use** — `sudo fuser -k <port>/tcp`
- **Browser cert warning** — see *Browser setup* below

---

## Browser setup (dev only)

Dev uses mkcert for local SSL. One-time setup:

```
sudo apt install -y libnss3-tools mkcert
mkcert -install
```

If using Chrome on Ubuntu, use the deb version (not snap) so it can access the trust store.

---

## Quick reference

- **Service names:** `group.service` (e.g. pizza.web)
- **Hostnames:** `pizza.do` (live), `pizza.do.dev` (dev)
- **Manifests:** `.321.yml` in each service repo — declares entry point, runner, required env
- **Secrets:** `secrets/<name>.env`, managed from dashboard
- **Perl deps:** each service installs into `./local/` (gitignored)
- **Deploys are safe to repeat** — clicking DEPLOY twice won't break anything
