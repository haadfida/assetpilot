import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildGraph, collectTouches, findImpact, MAX_NODES } from "./graph";
import { layoutGraph } from "./layout";
import { initialSession, sessionReducer, type Run } from "./runReducer";
import type { AgentEvent } from "./types";

// Fold a recorded replay (db/replays/*.json) into a Run, the way the stream would.
const REPLAYS = fileURLToPath(new URL("../../../db/replays", import.meta.url));
function runFrom(slug: string): Run {
  const fixture = JSON.parse(readFileSync(join(REPLAYS, `${slug}.json`), "utf8"));
  let s = sessionReducer(initialSession, { type: "start", key: "k", prompt: fixture.prompt, mode: "replay" });
  fixture.steps.forEach((st: Record<string, unknown>, i: number) => {
    let event: AgentEvent | null = null;
    if (st.type === "progress" || st.type === "text") event = { type: st.type, step: i, delta: st.text as string };
    if (st.type === "tool_use") event = { type: "tool_call", step: i, id: st.id as string, name: st.name as string, input: st.input as Record<string, unknown> };
    if (st.type === "tool_result")
      event = { type: "tool_result", step: i, tool_use_id: st.tool_use_id as string, name: st.name as string, is_error: st.is_error as boolean, output: st.output as never, duration_ms: st.duration_ms as number };
    if (event) s = sessionReducer(s, { type: "event", key: "k", event });
  });
  return s.runs[0];
}

describe("graph model", () => {
  it("builds the impact graph for DB-Server from the recording, within the node budget", () => {
    const run = runFrom("db-server-outage");
    const impact = findImpact(run)!;
    expect(impact.data.root.name).toBe("DB-Server");
    const g = buildGraph(impact, null, collectTouches(run), { showPeople: true })!;
    expect(g.source).toBe("impact");
    expect(g.edgesKnown).toBe(false);
    const root = g.nodes.find((n) => n.root)!;
    expect(root.id).toBe("asset:AP-00502");
    expect(g.nodes.filter((n) => n.kind === "service")).toHaveLength(12);
    expect(g.nodes.filter((n) => n.kind === "asset" && !n.root)).toHaveLength(25);
    expect(g.nodes.find((n) => n.kind === "more")?.label).toBe("+27 assets more");
    expect(g.nodes.length).toBeLessThanOrEqual(MAX_NODES);
    // Without the subgraph only direct (depth 1) dependents hang off the root.
    expect(g.edges.filter((e) => e.source === root.id && e.kind === "depends_on")).toHaveLength(5);
    // Every person is linked to what they own or hold, or to the overflow node.
    const people = g.nodes.filter((n) => n.kind === "person");
    expect(people.length).toBe(25);
    for (const p of people) expect(g.edges.some((e) => e.target === p.id)).toBe(true);
    expect(g.people.find((p) => p.name === "Morton Hammes")?.owns).toContain("Billing API");
    // People are listed but not drawn by default.
    expect(buildGraph(impact, null, [])!.nodes.some((n) => n.kind === "person")).toBe(false);
  });

  it("uses subgraph edges, drawn from the dependency to its dependent", () => {
    const run = runFrom("email-gateway-outage");
    const impact = findImpact(run)!;
    const services = impact.data.services.map((s, i) => ({ id: 100 + i, name: s.name, criticality: s.criticality, owner_id: null, depth: s.depth }));
    const sub = {
      root: { type: "Service" as const, id: 1, name: "Email Gateway" },
      services,
      assets: [{ id: 999, tag: "AP-09999", name: "Unlisted laptop", category: "laptop", status: "available", custodian_id: null, depth: 3 }],
      people: [],
      edges: [
        { source: { type: "Service" as const, id: 100 }, target: { type: "Service" as const, id: 1 }, kind: "depends_on" },
        { source: { type: "Service" as const, id: 103 }, target: { type: "Service" as const, id: 100 }, kind: "depends_on" },
        { source: { type: "Asset" as const, id: 999 }, target: { type: "Service" as const, id: 103 }, kind: "depends_on" },
        // A depth-2 service that also depends on the root directly: not a shortest-path edge.
        { source: { type: "Service" as const, id: 103 }, target: { type: "Service" as const, id: 1 }, kind: "depends_on" },
      ],
    };
    const g = buildGraph(impact, sub, [], { showPeople: false })!;
    expect(g.edgesKnown).toBe(true);
    const ids = g.edges.map((e) => `${e.source} -> ${e.target}`);
    expect(ids).toContain(`service:Email Gateway -> service:${services[0].name}`);
    expect(ids).toContain(`service:${services[0].name} -> service:${services[3].name}`);
    // An edge to an asset beyond the 25-item list goes to the overflow node.
    expect(ids).toContain(`service:${services[3].name} -> more:impact`);
    expect(ids).not.toContain(`service:Email Gateway -> service:${services[3].name}`);
    expect(g.crossEdges).toBe(1);
    expect(g.nodes.some((n) => n.kind === "person")).toBe(false);
  });

  it("highlights assets touched by search and schedule_maintenance, anchored on tool nodes", () => {
    const run = runFrom("dc1-warranty-maintenance");
    const touches = collectTouches(run);
    expect(touches.map((t) => [t.name, t.assets.map((a) => a.tag)])).toEqual([
      ["search_assets", ["AP-00502", "AP-00503", "AP-00505"]],
      ["schedule_maintenance", ["AP-00502", "AP-00503", "AP-00505"]],
    ]);
    const g = buildGraph(null, null, touches)!;
    expect(g.source).toBe("tools");
    const db = g.nodes.find((n) => n.id === "asset:AP-00502")!;
    expect(db.label).toBe("DB-Server");
    expect(db.touchedBy).toEqual(["search_assets", "schedule_maintenance"]);
    expect(g.nodes.filter((n) => n.kind === "tool")).toHaveLength(2);
    expect(g.edges.filter((e) => e.kind === "touched")).toHaveLength(6);
  });

  it("marks the asset of a failed checkout as errored and links checkouts to people", () => {
    const conflict = buildGraph(null, null, collectTouches(runFrom("checkout-conflict-ap-00016")))!;
    expect(conflict.nodes.find((n) => n.id === "asset:AP-00016")?.status).toBe("error");

    const ok = buildGraph(null, null, collectTouches(runFrom("checkout-macbook")))!;
    expect(ok.edges).toContainEqual(expect.objectContaining({ source: "asset:AP-00004", target: "person:Shannon Kuhn", kind: "checked_out" }));
  });

  it("returns null when a run touched nothing", () => {
    const run = runFrom("fleet-summary");
    expect(buildGraph(findImpact(run), null, collectTouches(run))).toBeNull();
  });

  it("lays every node out without overlaps", () => {
    const run = runFrom("db-server-outage");
    for (const g of [buildGraph(findImpact(run), null, [])!, buildGraph(null, null, collectTouches(runFrom("dc1-warranty-maintenance")))!]) {
      const pos = [...layoutGraph(g).values()];
      expect(pos).toHaveLength(g.nodes.length);
      for (let i = 0; i < pos.length; i++)
        for (let j = i + 1; j < pos.length; j++) {
          const a = pos[i];
          const b = pos[j];
          const overlap = a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
          expect(overlap, `${a.id} overlaps ${b.id}`).toBe(false);
        }
    }
  });
});
