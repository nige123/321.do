# CLAUDE.md

## Project Overview

321.do — 3... 2... 1... deploy! A standalone deploy and log analysis service for managing Perl/Mojolicious services. Replaces in-app deploy endpoints that caused outages by restarting themselves mid-request.

## Tech Stack

- **Language:** Perl 5.42 (`Mojo::Base -base, -signatures`)
- **Framework:** Mojolicious::Lite
- **Config:** YAML service registry (`services.yml`)
- **No database** — stateless, config-driven

## Architecture

Single lightweight daemon on port **9999**. Hypnotoad hot restarts for zero-downtime deploys.

### Endpoints

```
GET  /                            — Dashboard UI
GET  /ui/service/:name            — Service detail UI
GET  /services                    — list all services and their status
GET  /service/:name/status        — detailed status
POST /service/:name/deploy        — deploy: git pull → cpanm → hypnotoad restart
GET  /service/:name/logs          — tail logs (?type=stderr&n=100)
GET  /service/:name/logs/search   — search logs (?q=error&type=stderr&n=50)
GET  /service/:name/logs/analyse  — error/warning aggregation
GET  /health                      — health check (public, no auth)
```

### Auth

Bearer token required in production. Skipped in development mode.
Token from `DEPLOY_TOKEN` env var or `deploy_token.txt`.

## Development

```bash
perl bin/321.pl daemon -l http://127.0.0.1:9999
prove -lr t
```

## Coding Conventions

- Four space indentation
- JSON responses: `{ status, message, data }`
- All endpoints require Bearer token auth in production (except GET /health)
