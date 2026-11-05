# AssetPilot

An AI operations assistant for IT asset inventories. Ask it questions in plain
language ("which laptops go out of warranty this quarter?"), have it take actions
(check assets out and in, schedule maintenance), and run impact analysis over the
dependency graph ("what breaks, and who is affected, if this switch dies?").

This repository is at **milestone M1: the domain model and the JSON API**. The
agent, UI and MCP server come in later milestones. All data is synthetic.

## Stack

Ruby 3.2.3, Rails 8.1 (API mode), PostgreSQL 16, RSpec, Faker.

## Quick start

```sh
bin/setup            # installs gems, starts Postgres (docker compose), prepares and seeds the DB
bin/rails s          # http://localhost:3000
bundle exec rspec
```

Postgres runs from `docker-compose.yml` (`docker compose up -d db` or `docker-compose up -d db`).
Connection settings come from `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`
(defaults: localhost, 5432, postgres, postgres). The `pg` gem needs libpq headers
(`brew install libpq` on macOS; `libpq-dev` on Debian/Ubuntu).

Seeds are deterministic (`Faker::Config.random = Random.new(42)`): about 500 assets,
60 people, 8 locations, 12 services and 200 dependency edges. `bin/rails db:seed` wipes and
rebuilds the data.

## Data model

Asset, Person, Location, Service, Checkout, MaintenanceTask, and Dependency, an
adjacency table with typed endpoints. A row reads "source `depends_on` / `runs_on`
target", where both ends are an Asset or a Service. If the target fails, the source is impacted.

## API

| Endpoint | Notes |
| --- | --- |
| `GET /api/assets` | `q` (name, tag, serial), `status`, `category`, `location_id`, `custodian_id`, `warranty_before=YYYY-MM-DD`, `page`, `per_page` (max 100) |
| `GET /api/assets/:id` | includes the open checkout and maintenance tasks |
| `GET /api/people`, `/api/people/:id` | `q`, `department` |
| `GET /api/services`, `/api/services/:id` | `criticality` |
| `GET /api/impact/:type/:id` | `type` is `asset` or `service`; optional `max_depth` (default 10, max 25) |

Impact analysis uses a recursive CTE that walks dependents of the node, tracks the path per
branch to cut cycles, and stops at the depth limit. It returns the dependent services and
assets (with their hop distance), plus the affected people: service owners and asset custodians.

```sh
curl localhost:3000/api/impact/asset/42?max_depth=5
```

## Roadmap

- **M1** (this repo): domain, seeds, REST API, impact analysis, specs, CI.
- **M2**: the agent. Natural-language Q&A and tool-using actions (checkout/checkin, scheduling maintenance).
- **M3**: React UI and an MCP server exposing the same tools.
- **M4**: evals for the agent, then deployment.

## License

MIT
