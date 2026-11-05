# MCP demo script: 60-second GIF

Goal: Claude Code answers "what breaks if the DB server goes down?" by calling `impact_analysis` over MCP.
Records well at 100x30 terminal, large font, dark theme. Target length 45-60 s.

## Setup (off camera)

```sh
docker-compose up -d db && bin/rails db:setup      # seeded data, once
claude mcp add assetpilot -- "$(pwd)/bin/mcp"      # stdio; use --scope local so it stays out of other projects
claude mcp list                                    # assetpilot: connected
```

Open a fresh `claude` session in any directory. Clear the screen. Start the recorder.

## Script

| t | Action | What the viewer sees |
| --- | --- | --- |
| 0:00 | Type `/mcp` and Enter | `assetpilot` connected, 7 tools. Arrow into it to show read tools flagged read-only. |
| 0:08 | Esc, then type the prompt: `What breaks if the DB-Server asset goes down? Who do I need to tell?` | Prompt appears. |
| 0:14 | Claude proposes `assetpilot - impact_analysis (MCP)` with `node_type: asset`, `node: DB-Server`. Approve once ("Yes, and don't ask again" is fine for read-only tools). | Permission prompt shows the tool and arguments. |
| 0:22 | Result renders | Counts of affected assets and services, criticality breakdown, people to notify. |
| 0:35 | Claude summarizes in prose: the critical services, the owners to notify. | Final answer. |
| 0:45 | Follow-up: `Check out a spare laptop to Ada` | Claude calls `checkout_asset`; the permission prompt flags it as a write. Decline it (Esc) to show nothing changes. |
| 0:55 | Stop recording. | |

## Notes

- If the DB asset's name differs, check `db/seeds.rb` or run `bin/rails runner 'puts Asset.where("name ILIKE ?", "%db%").pluck(:tag, :name)'`.
- The same question in the web agent replays from `db/replays/db-server-outage.json`, so the two answers can be compared side by side.
- Keep it deterministic: do not edit seeds between takes. For a read-only take, register with `-e MCP_ALLOW_WRITES=0`.
- Convert with `gifski` or `ffmpeg -i demo.mov -vf "fps=12,scale=900:-1" demo.gif`.
