# 321 — How to use

3... 2... 1... deploy! This is your dashboard for managing Perl web services.

**Dashboard:** https://321.do.dev/ (dev) or https://321.do/ (prod)
**Login:** `321` / `kaizen`

---

## Adding a new service

Three steps to go from "I have a repo" to "it's running behind SSL."

### Step 1: Create a config file

Create `services/<name>.yml` with the service details:

```yaml
name: foo.web
repo: /home/s3/foo.web
branch: main
bin: bin/app.pl
targets:
  dev:
    host: foo.do.dev
    port: 9600
    runner: morbo
  live:
    host: foo.do
    port: 9600
    runner: hypnotoad
```

**Need system packages?** Add them so the installer knows:
```yaml
apt_deps:
  - libexpat1-dev
  - libpng-dev
```

**Need secrets?** Put them in `secrets/foo.web.env`:
```
DB_PASS=supersecret
API_KEY=abc123
```

### Step 2: Install

```
321 install foo.web
```

This clones the repo, installs Perl deps, sets up nginx + SSL, and starts the service. If system packages are missing, it tells you exactly what to run.

### Step 3: Check it's working

Open the dashboard. Your service should have a green light. Click into it and hit **VISIT** to open the site.

If something's wrong, check the **deploy** tab in the terminal panel — failed steps are highlighted in red with the full error output.

---

## Updating a service

Once a service is installed, you have four buttons on the service detail page:

| Button | What it does | When to use it |
|--------|-------------|----------------|
| **DEPLOY** | Pull code, install deps, run migrations, restart | Regular deployments |
| **UPDATE** | Pull code, install deps, run migrations (no restart) | When you want to check everything works before bouncing the service |
| **MIGRATE** | Run `bin/migrate` only | Re-run a migration without touching code |
| **RESTART** | Restart the service + verify it's responding | After changing config or env vars |

All four show per-step output in the **deploy** tab. If a step fails, it expands automatically with the error.

**From the CLI:**
```
321 go foo.web          # same as DEPLOY
321 update foo.web      # same as UPDATE
321 migrate foo.web     # same as MIGRATE
321 restart foo.web     # same as RESTART
```

**On dev,** `321 go` skips the git pull — it just restarts with your local code changes.

---

## Migrations

If your service repo has a `bin/migrate` script, 321 runs it automatically during DEPLOY and UPDATE (between installing deps and restarting). If the script fails (non-zero exit), the deploy stops before restarting — so a bad migration won't take down a running service.

Use whatever migration tool you like. 321 only cares about the exit code.

---

## If something goes wrong

| What you see | What to do |
|---|---|
| Deploy failed at `apt_deps` | Run the `sudo apt install ...` command shown in the error |
| Deploy failed at `cpanm` | Usually a missing system library. Add it to `apt_deps` in the YAML |
| Deploy failed at `git_pull` | Check the `branch:` in your YAML matches the actual branch name (main vs master) |
| Service won't start / port not responding | Check the **stderr** tab for crash output |
| Port already in use | `sudo fuser -k <port>/tcp` to kill the orphan process |
| Browser shows certificate warning | See *Browser setup* below |

**After editing a YAML file,** restart 321 to pick up the change:
```
hypnotoad bin/321.pl
```

---

## Browser setup (dev only)

Dev uses mkcert for local SSL. One-time setup:

```
sudo apt install -y libnss3-tools mkcert
mkcert -install
```

**Important:** If you're using Chrome on Ubuntu, use the deb version, not the snap. The snap can't access the certificate trust store. See the detailed instructions in the troubleshooting section of CLAUDE.md if you hit cert warnings.

---

## Quick reference

- **Hostnames:** `foo.do` (live), `foo.do.dev` (dev)
- **Secrets:** `secrets/<name>.env`, one `KEY=value` per line, gitignored
- **Perl deps:** each service installs into its own `./local/` directory (gitignore `/local/`)
- **Deploys are safe to repeat** — clicking DEPLOY twice won't break anything
