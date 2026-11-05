# Demo GIF: 60-second shot list

The GIF covers the web UI and Claude Code in one take: open the app, run the impact chip, watch the graph
light up, check an asset in from its chip, then add the MCP server in Claude Code and call
`impact_analysis` there. It needs no Anthropic key: the web part is a replay of recorded tool calls
(labelled as synthetic), and the Claude Code part uses your own Claude Code login.

## Setup (off camera)

```sh
docker-compose up -d db && bin/rails db:setup        # deterministic seed, once
bin/rails s -p 3100                                  # API
cd frontend && npm run dev                           # http://localhost:5173
claude mcp remove assetpilot 2>/dev/null || true     # so the add is shown fresh on camera
```

- Browser: a 1440x900 window at 100% zoom, light theme. Open `http://localhost:5173/?speed=2` so replays
  stream at twice the recorded pace, then reload so the welcome screen is clean. The "People to notify"
  column starts collapsed.
- Terminal: 100x30, large font, dark theme, `cd` into the repo, screen cleared. Keep it in a second window
  or a split you can cut to.
- Recorder: 30 fps (convert to 12 fps later). Hide the mouse-click highlight. Rehearse once: a replay
  never changes the database, so takes are repeatable.

## Shot list

| Time | Shot | Action | What the viewer must see |
| --- | --- | --- | --- |
| 0:00-0:04 | Browser, full window | The app is open on the welcome screen. Hold. | Header: **AssetPilot**, badge **Replay · synthetic recording**. Starter cards on the left, an empty graph on the right ("The blast radius draws here"). |
| 0:04-0:07 | Browser, chat | Click the starter card **What breaks if DB-Server goes down?** | The prompt bubble, then the progress note "I'll trace everything that depends on DB-Server…". |
| 0:07-0:12 | Browser, chat | The `impact_analysis` tool card appears and turns green. | The card shows `node_type: asset · node: DB-Server` and "12 services, 52 assets, 30 people affected". |
| 0:12-0:20 | Browser, graph (slow zoom on the right half is fine) | The graph draws and fits. | The red **DOWN · DB-Server** node on the left, the services by hop distance fanning out (Billing API, Payroll and Data Warehouse first), the legend and counts. |
| 0:20-0:24 | Browser, graph | Click **People to notify** in the right-hand column. | The column opens beside the graph and the canvas re-fits: no node is covered. 25 of 30 people, with what they own. |
| 0:24-0:27 | Browser, chat | Hover the `impact_analysis` card. | The nodes it produced stay lit and the rest dim. |
| 0:27-0:31 | Browser, chat | Scroll to the chips under the composer and click **Check in asset AP-00014**. | A new run starts, with "Checking in AP-00014." |
| 0:31-0:37 | Browser, both panes | The `checkin_asset` card turns green; the answer streams. | "Done: **AP-00014 Nienow MacBook Pro 14** is checked in from Lonny Harvey…, days late." In the graph, the asset node is highlighted, anchored on the `checkin_asset` tool node. |
| 0:37-0:40 | Cut to terminal | Type `claude mcp add assetpilot -- "$(pwd)/bin/mcp"` and press Enter. | `Added stdio MCP server assetpilot…`. |
| 0:40-0:43 | Terminal | Type `claude` and press Enter, then `/mcp` and Enter. | `assetpilot` connected, 7 tools. Press Esc. |
| 0:43-0:47 | Terminal | Type `What breaks if DB-Server goes down?` and press Enter. | Claude proposes `assetpilot - impact_analysis (MCP)` with `node_type: "asset"`, `node: "DB-Server"`. |
| 0:47-0:50 | Terminal | Approve the call (read-only tool). | The tool result: counts, criticality breakdown, people. |
| 0:50-0:58 | Terminal | Claude's answer streams. | The same 12 services / 52 assets / 30 people as the web graph, with service owners to call. |
| 0:58-1:00 | Terminal | Hold on the answer, then end. | |

## Captions (optional, burned in)

- 0:04 "Replays of real tool calls, no API key needed"
- 0:12 "Impact analysis: recursive CTE over the dependency graph"
- 0:27 "Mutating tools work the same way"
- 0:37 "The same tools over MCP, in Claude Code"

## Notes

- The check-in chip is a replay, so the inventory is not changed and you can re-record freely. In a live
  run (your key in Settings) the same chip checks AP-00014 in for real.
- If Claude Code asks for permission each time, choose "Yes, and don't ask again" for `impact_analysis`
  during the rehearsal so the take stays short. Only do that for read-only tools.
- To cut the Claude Code part shorter, register the server off camera and start at the prompt (0:43).
- Convert with `ffmpeg -i demo.mov -vf "fps=12,scale=1200:-1:flags=lanczos" -loop 0 demo.gif`, or with
  `gifski --fps 12 --width 1200`. Keep it under about 10 MB for the README.
- The MCP-only 60-second script is in [mcp-demo.md](mcp-demo.md).
