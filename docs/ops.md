# 321 — Operator Guide

3... 2... 1... deploy!

---

## Quick start

```
321 init                    # create 321.yml in your repo
321 install love.web        # first-time setup (local)
321 install love.web live   # first-time setup (production)
321 go love.web live        # deploy to production
```

---

## Day-to-day

| Action | Command |
|--------|---------|
| Deploy | `321 go <service> [target]` |
| Restart | `321 restart <service> [target]` |
| Status | `321 status [service] [target]` |
| Logs | `321 logs <service> [target]` |
| Start | `321 start <service> [target]` |
| Stop | `321 stop <service> [target]` |

Skip the service name if you're in its repo directory. Skip the target for local dev.

```
cd /home/s3/love.honeywillow.com
321 restart              # restarts love.web locally
321 restart live         # restarts love.web on production
321 logs --stderr        # tail local stderr
321 logs live            # tail production stdout
```

---

## Adding a new service

```
cd /home/s3/my-new-app
321 init
```

This creates a `321.yml` with your service name, git remote, and entry point pre-filled. Edit it, then:

```
321 install my.app
321 install my.app live
```

---

## Deploying to production

```
321 go love.web live
```

This SSHes into the live server and runs: git pull → apt deps → cpanm → migrate → restart → port check.

On dev, `321 go love.web` skips git pull (uses your local code).

---

## Targets

- **dev** — local machine, morbo (auto-reload)
- **live** — remote server via SSH, hypnotoad (zero-downtime)

Defined in each service's `321.yml`:

```yaml
dev:
    host: love.honeywillow.com.dev
    port: 8888
    runner: morbo

live:
    ssh: ubuntu@ec2-....compute.amazonaws.com
    ssh_key: ~/.ssh/kaizen-nige.pem
    host: love.honeywillow.com
    port: 8888
    runner: hypnotoad
```

---

## Secrets

Secret values live in `secrets/<name>.env` (chmod 600, gitignored). Declare what's needed in `321.yml`:

```yaml
env_required:
    DATABASE_URL: "Postgres connection string"
```

Set values manually:
```
echo 'DATABASE_URL=postgresql://...' >> secrets/love.web.env
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Service won't start | `321 logs <service> --stderr` |
| Deploy fails at git_pull | Check `branch:` in 321.yml |
| Deploy fails at apt_deps | 321 auto-installs, check sudo |
| Port already in use | `sudo fuser -k <port>/tcp` |
| "Unknown service" | Run `321 init` in the repo |
| Cert warning (dev) | `mkcert -install` |

---

## All commands

```
321 init                    # scaffold 321.yml in current repo
321 install <svc> [target]  # first-time full setup
321 go <svc> [target]       # deploy (pull + deps + restart)
321 start <svc> [target]    # start
321 stop <svc> [target]     # stop
321 restart <svc> [target]  # restart + verify
321 update <svc> [target]   # pull + deps (no restart)
321 migrate <svc> [target]  # run bin/migrate
321 status [svc] [target]   # running state
321 list [target]           # all services
321 logs <svc> [target]     # tail logs (--stderr, --search=X, --analyse)
321 rebuild [target]        # regenerate ubic service files
321 dash                    # start local web dashboard
```
