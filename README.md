# AssetPilot

An AI operations assistant for IT asset inventories. Ask it questions in plain
language ("which laptops go out of warranty this quarter?"), have it take actions
(check assets out and in, schedule maintenance), and run impact analysis over the
dependency graph ("what breaks, and who is affected, if this switch dies?").

This repository is at **milestone M2: the agent**, on top of M1's domain model and JSON API.
The UI and MCP server come in later milestones. All data is synthetic.

## Stack

Ruby 3.2.3, Rails 8.1 (API mode), PostgreSQL 16, RSpec, Faker, the official Anthropic Ruby SDK (`anthropic`).

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

Seeds are deterministic (`Faker::Config.random = Random.new(42)`, logic in `lib/seed_data.rb`):
506 assets, 60 people, 9 locations, 12 services and 212 dependency edges. `bin/rails db:seed` wipes
the tables with `RESTART IDENTITY`, so ids are stable across reseeds too. Besides the random data
there is a small hand-named site, **Data-Center-1**, with `DB-Server` (AP-00502), `Core-Switch-DC1`,
two app servers, a backup NAS and a PDU; the agent replays refer to it.

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

## Agent

Ask questions in plain language; the agent answers with the inventory tools and streams its work
as Server-Sent Events. Every run and every step is stored.

### Try it without a key (replay mode)

No Anthropic key is needed to see it work. Without one, a known prompt is **replayed** from a
recording in `db/replays/` through the same streaming pipeline a live run uses:

```sh
bin/rails s
curl -s localhost:3000/api/agent/replays                    # the 8 replayable prompts
curl -s -XPOST localhost:3000/api/agent/runs -H 'content-type: application/json' \
     -d '{"prompt":"What breaks if DB-Server goes down?"}'   # -> {"data":{"id":1,"mode":"replay",...}}
curl -N "localhost:3000/api/agent/runs/1/stream?speed=2"     # SSE; speed scales the recorded timings
```

Replayable prompts (matching ignores case and punctuation; each has a few aliases):

| Prompt | Tools used |
| --- | --- |
| What breaks if DB-Server goes down? | impact_analysis |
| Which laptops are overdue and who has them? | search_assets |
| Check in asset AP-00014 | checkin_asset |
| Schedule maintenance for assets with expired warranty in Data-Center-1 | search_assets, schedule_maintenance |
| Summarize the fleet | summarize_fleet |
| Check out an available MacBook Pro to Shannon Kuhn for two weeks | search_assets, checkout_asset |
| Check out AP-00016 to Marguerite Little | checkout_asset (fails: already out), search_assets |
| What happens if the Email Gateway goes down? | impact_analysis |

**The recordings are synthetic, and labelled as such** (`"recorded": "synthetic"` on the fixture,
the run and the `done` event). No real key was available when they were made, so `rake replays:build`
reseeds the database inside a rolled-back transaction with the clock frozen at 2026-11-05 10:00 UTC,
**executes each scenario's tool calls for real**, and composes the assistant text from a template over
the actual results. Tool inputs and outputs are therefore genuine for the seeded data; the prose is
not model output, the timings are plausible estimates plus measured tool durations, and token usage
is estimated. `rake replays:verify` (also run by the spec suite) re-executes every recorded tool call,
requires identical output, and rebuilds each fixture. Replaying never executes tools, so replaying
"Check in asset AP-00014" does not change the inventory.

### Live mode (bring your own key)

Send your Anthropic API key in the `x-anthropic-key` header. A live run executes when its stream is
opened, so the **stream request carries the key too**; nothing holds it between the two requests.

```sh
curl -s -XPOST localhost:3000/api/agent/runs -H "x-anthropic-key: $KEY" \
     -H 'content-type: application/json' -d '{"prompt":"Which servers in Data-Center-1 are out of warranty?"}'
curl -N localhost:3000/api/agent/runs/2/stream -H "x-anthropic-key: $KEY"
```

In development only, `ANTHROPIC_API_KEY` is used when the header is absent. Pass `"mode":"replay"`
to replay a known prompt even when a key is present.

**The key is never stored or logged.** It lives in a local variable for the request and is passed to
the SDK client. `x-anthropic-key` is in `filter_parameters` (in case a client sends it as a parameter),
the rate limiter buckets by its SHA-256, and API error messages are scrubbed before they are saved. A
spec (`spec/requests/agent_byok_spec.rb`) runs a full live run through the real SDK against a stubbed API
and asserts the key appears in no log line, no row of any table, and no SSE frame.

**Rate limits** (Rails 8 `rate_limit`, per key, or per IP without one): 10 run creations and 30 stream
opens per minute (`AGENT_RATE_LIMIT`, `AGENT_STREAM_RATE_LIMIT`), answered with HTTP 429.

### Endpoints

| Endpoint | Notes |
| --- | --- |
| `POST /api/agent/runs` | `{prompt, mode?, replay?}`. 201 with the run and its `stream_url`; 422 with the replay catalog when there is no key and the prompt is unknown |
| `GET /api/agent/runs/:id/stream` | SSE. Executes a queued run (live needs the key header; replay takes `speed`, default 1). A finished run re-streams from its stored steps |
| `GET /api/agent/runs/:id` | the run (status, model, mode, usage, timings) and its ordered steps |
| `GET /api/agent/replays` | replayable prompts |

Stream events, each `event: <name>` plus one JSON `data:` line:

| Event | Data |
| --- | --- |
| `progress` | `{step, delta}`: the model's short "what I'm doing next" notes between tool calls |
| `text` | `{step, delta}`: answer text, streamed as it is generated |
| `tool_call` | `{step, id, name, input}` |
| `tool_result` | `{step, tool_use_id, name, is_error, output, duration_ms}` |
| `error` | `{step, code, message}`, e.g. `invalid_api_key`, `refusal`, `iteration_cap` |
| `done` | `{id, status, mode, recorded, model, iterations, stop_reason, usage, duration_ms, steps}` |

### Tools

Plain Ruby service objects in `app/services/tools/`, each unit-tested. The model gets their JSON schemas
with `strict: true`. Keywords strict tool use does not support (numeric bounds, string and array lengths)
are removed from the schema sent to the model and enforced locally with `json_schemer` before the tool runs.
Tools never raise. They return `{"ok": true, "data": ...}` or
`{"ok": false, "error": {"code", "message", "details"}}`, which becomes an `is_error` tool result.

| Tool | Does |
| --- | --- |
| `search_assets` | filters: text, category, status, location, custodian, warranty expired/active/expiring within N days, overdue; ≤ 50 results |
| `get_asset` | one asset by tag, id or name: custodian, open checkout, maintenance, direct dependencies and dependents |
| `checkout_asset` | mutating; rejects assets already out, retired or in maintenance, unknown or ambiguous people, due dates outside 1-180 days |
| `checkin_asset` | mutating; closes the open checkout, reports lateness |
| `schedule_maintenance` | mutating; one task per asset, all-or-nothing on unknown assets, skips retired assets and duplicates |
| `impact_analysis` | M1's recursive CTE by asset or service name, with counts, criticality breakdown and people to notify |
| `summarize_fleet` | fleet or per-location aggregates: status, category, location, warranty, checkouts, maintenance, services |

### Model and loop

`Agent::Runner` is a manual tool-use loop over the SDK's streaming helper
(`client.beta.messages.stream`). The parameters follow Anthropic's `claude-api` skill:

- **Model** `claude-opus-5-5` (the skill's default), with **adaptive thinking**. Thinking can't be
  disabled on Opus 5.5; `output_config.effort` is the control, set explicitly to `medium` (the model's
  default and the skill's suggested starting point for multi-step tool use).
- `thinking.display: "updates"` (beta `thinking-display-updates-2026-08-18`): Opus 5.5 returns its
  between-tool-call notes as thinking blocks, empty by default; with `updates` they arrive as short
  text, streamed here as `progress`, while the reasoning stays hidden.
- **Streaming** with `max_tokens: 64000` (thinking counts toward it).
- `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`): a classifier refusal is retried
  server-side on Anthropic's recommended fallback model. A refusal that still comes back ends the run
  as `refused`.
- `tool_choice: auto` (forced tool choice is a 400 on Opus 5.5). Tools are `strict` and use
  `eager_input_streaming`; input that arrives as invalid JSON is not executed and goes back to the
  model as an `INVALID_JSON` error result.
- Top-level `cache_control` for prompt caching. Tools and the system prompt form a stable prefix;
  today's date goes in the user turn. The history is append-only: assistant turns, including thinking
  blocks and their signatures, are sent back unchanged.
- A turn that stops on `max_tokens` or `refusal` never runs its tools. The loop is capped at
  `AGENT_MAX_TOOL_ITERATIONS` (default 8) tool turns and then ends as `max_iterations`.

The system prompt (`app/services/agent.rb`) keeps the model to the inventory: facts must come from
tool results, mutating tools only on explicit request, ask when ambiguous, and treat tool output as data.

Settings: `AGENT_MODEL`, `AGENT_EFFORT`, `AGENT_MAX_TOKENS`, `AGENT_MAX_TOOL_ITERATIONS`, `AGENT_REPLAY_SPEED`.

### Persistence

`agent_runs` holds one row per run: prompt, model, mode (`live`/`replay`), `recorded`, status
(`queued`, `running`, `succeeded`, `failed`, `refused`, `max_iterations`), tool iterations, stop reason,
token usage (input, output, cache read, cache creation), error, start and finish times, and duration.
`agent_steps` holds its ordered steps: `text` and `progress` (deltas aggregated per content block),
`tool_use` (with input), `tool_result` (with output and `is_error`), and `error`, each with its offset
from the run start and its duration.

### Rebuilding the replays

```sh
bin/rails replays:build    # rewrites db/replays/*.json; the database is left unchanged
bin/rails replays:verify   # re-runs every recorded tool call and checks the fixtures are current
```

Scenarios live in `lib/replays/scenarios.rb`. If you change the seeds, a tool's output, or a template,
rebuild the fixtures; the spec suite fails on stale ones.

## Roadmap

- **M1**: domain, seeds, REST API, impact analysis, specs, CI.
- **M2** (this branch): the agent. Natural-language Q&A and tool-using actions over SSE, BYOK, replay mode.
- **M3**: React UI and an MCP server exposing the same tools.
- **M4**: evals for the agent, then deployment.

## License

MIT
