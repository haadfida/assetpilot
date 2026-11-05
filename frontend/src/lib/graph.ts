// Turns a run's tool results into a graph model for the dependency panel. Pure (unit-tested).
//
// impact_analysis gives the impacted services, assets and people (lists capped at 25) with their hop
// distance, but no edges; the edges come from GET /api/impact/:type/:id (fetched by the panel), which
// returns the subgraph with ids. Nodes are keyed by service name, asset tag and person name, which is
// how the tool output identifies them. Assets touched by the other tools are highlighted, and added
// when the graph does not already contain them.

import type { Block, Run, ToolBlock } from "./runReducer";
import type { Subgraph } from "./api";

export type NodeKind = "service" | "asset" | "person" | "tool" | "more";

export interface GraphNode {
  id: string;
  kind: NodeKind;
  label: string;
  sublabel?: string;
  criticality?: string;
  category?: string;
  depth?: number;
  root?: boolean;
  impacted?: boolean;
  /** Tool names (other than impact_analysis) that touched this node. */
  touchedBy: string[];
  /** Tool-call ids that produced or touched this node, for focus highlighting. */
  toolIds: string[];
  status?: "ok" | "error";
}

export type EdgeKind = "depends_on" | "runs_on" | "owns" | "custodian" | "touched" | "checked_out" | "more";

export interface GraphEdge {
  id: string;
  source: string;
  target: string;
  kind: EdgeKind;
}

export interface GraphModel {
  nodes: GraphNode[];
  edges: GraphEdge[];
  /** "impact" when an impact_analysis result is drawn; "tools" when only touched assets are. */
  source: "impact" | "tools";
  title: string;
  counts?: { services: number; assets: number; people: number };
  /** Whether dependency edges between impacted nodes are known (from the subgraph endpoint). */
  edgesKnown: boolean;
  /** Dependency edges left out because they are not on a shortest path from the failing node. */
  crossEdges: number;
  /** People to notify, with what they own or hold (also drawn as nodes when showPeople is set). */
  people: { name: string; department: string; owns: string[] }[];
}

export const MAX_NODES = 80;

// --- extracting what the tools touched ---------------------------------------------------------

interface ImpactData {
  root: { type: "asset" | "service"; name: string; tag?: string; criticality?: string };
  counts: { services: number; assets: number; people: number };
  services: { name: string; criticality: string; depth: number; owner: string | null }[];
  assets: { tag: string; name: string; category: string; depth: number; custodian: string | null }[];
  people: { name: string; email: string; department: string }[];
  truncated?: { services: boolean; assets: boolean; people: boolean };
}

export interface ImpactSource {
  toolId: string;
  data: ImpactData;
}

export interface AssetRef { tag: string; name?: string; category?: string; status?: string }

export interface ToolTouch {
  toolId: string;
  name: string;
  status: "running" | "ok" | "error";
  assets: AssetRef[];
  /** People an asset was checked out to / returned by, keyed by asset tag. */
  people: { name: string; tag: string; relation: "checked_out" }[];
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : undefined);

const tools = (blocks: Block[]) => blocks.filter((b): b is ToolBlock => b.kind === "tool");

/** The latest successful impact_analysis result of a run. */
export function findImpact(run: Run | undefined): ImpactSource | null {
  if (!run) return null;
  const found = tools(run.blocks)
    .filter((b) => b.name === "impact_analysis" && b.output?.ok === true)
    .pop();
  if (!found || found.output?.ok !== true) return null;
  const data = found.output.data as unknown as ImpactData;
  if (!isObj(data) || !isObj(data.root)) return null;
  return { toolId: found.id, data };
}

function assetRef(v: unknown): AssetRef | null {
  if (!isObj(v)) return null;
  const tag = str(v.tag);
  if (!tag) return null;
  return { tag, name: str(v.name), category: str(v.category), status: str(v.status) };
}

const TAG_RE = /^AP-\d+$/i;

/** Assets (and checkout people) each non-impact tool call touched, from its input and its output. */
export function collectTouches(run: Run | undefined): ToolTouch[] {
  if (!run) return [];
  return tools(run.blocks)
    .filter((b) => b.name !== "impact_analysis")
    .map((b) => {
      const assets: AssetRef[] = [];
      const people: ToolTouch["people"] = [];
      const add = (a: AssetRef | null) => {
        if (!a) return;
        const existing = assets.find((x) => x.tag === a.tag);
        if (existing) Object.assign(existing, Object.fromEntries(Object.entries(a).filter(([, v]) => v !== undefined)));
        else assets.push(a);
      };

      // input: { asset: "AP-00014" } or { assets: [...] }
      const inAsset = str(b.input.asset);
      if (inAsset && TAG_RE.test(inAsset)) add({ tag: inAsset.toUpperCase() });
      if (Array.isArray(b.input.assets)) for (const t of b.input.assets) if (typeof t === "string" && TAG_RE.test(t)) add({ tag: t.toUpperCase() });

      const out = b.output;
      if (out?.ok === true) {
        const d = out.data;
        if (Array.isArray(d.assets)) d.assets.forEach((a) => add(assetRef(a)));
        if (Array.isArray(d.scheduled)) d.scheduled.forEach((a) => add(assetRef(a)));
        if (Array.isArray(d.skipped)) d.skipped.forEach((a) => add(assetRef(a)));
        const single = assetRef(d.asset) ?? (str(d.tag) ? assetRef(d) : null);
        add(single);
        if (single && b.name === "checkout_asset" && isObj(d.person) && str(d.person.name)) {
          people.push({ name: str(d.person.name)!, tag: single.tag, relation: "checked_out" });
        }
      } else if (out?.ok === false && isObj(out.error.details)) {
        add(assetRef(out.error.details));
      }
      return { toolId: b.id, name: b.name, status: b.status, assets, people };
    })
    .filter((t) => t.assets.length > 0);
}

// --- building the model ------------------------------------------------------------------------

const serviceId = (name: string) => `service:${name}`;
const assetId = (tag: string) => `asset:${tag}`;
const personId = (name: string) => `person:${name}`;

export function buildGraph(
  impact: ImpactSource | null,
  subgraph: Subgraph | null,
  touches: ToolTouch[],
  { showPeople = false }: { showPeople?: boolean } = {},
): GraphModel | null {
  if (!impact && touches.length === 0) return null;

  const nodes = new Map<string, GraphNode>();
  const edges = new Map<string, GraphEdge>();
  const addEdge = (source: string, target: string, kind: EdgeKind) => {
    if (source === target || !nodes.has(source) || !nodes.has(target)) return;
    const id = `${source}->${target}`;
    if (!edges.has(id)) edges.set(id, { id, source, target, kind });
  };
  const addNode = (n: Omit<GraphNode, "touchedBy" | "toolIds"> & Partial<Pick<GraphNode, "touchedBy" | "toolIds">>) => {
    if (nodes.has(n.id) || nodes.size >= MAX_NODES) return nodes.get(n.id);
    const node: GraphNode = { touchedBy: [], toolIds: [], ...n };
    nodes.set(n.id, node);
    return node;
  };

  let title = "Assets touched by the agent";
  let edgesKnown = false;
  let crossEdges = 0;
  let people: GraphModel["people"] = [];

  if (impact) {
    const { data, toolId } = impact;
    const r = data.root;
    const rootId = r.type === "asset" ? assetId(r.tag ?? r.name) : serviceId(r.name);
    title = `Impact of ${r.name}${r.tag ? ` (${r.tag})` : ""} going down`;
    addNode({
      id: rootId,
      kind: r.type,
      label: r.name,
      sublabel: r.type === "asset" ? r.tag : r.criticality ? `${r.criticality} criticality` : "service",
      criticality: r.criticality,
      root: true,
      depth: 0,
      toolIds: [toolId],
    });
    for (const s of data.services ?? []) {
      addNode({ id: serviceId(s.name), kind: "service", label: s.name, sublabel: `${s.criticality} · ${hop(s.depth)}`,
                criticality: s.criticality, depth: s.depth, impacted: true, toolIds: [toolId] });
    }
    for (const a of data.assets ?? []) {
      addNode({ id: assetId(a.tag), kind: "asset", label: a.name, sublabel: `${a.tag} · ${a.category}`,
                category: a.category, depth: a.depth, impacted: true, toolIds: [toolId] });
    }

    const hiddenAssets = Math.max(0, (data.counts?.assets ?? 0) - (data.assets?.length ?? 0));
    const hiddenServices = Math.max(0, (data.counts?.services ?? 0) - (data.services?.length ?? 0));
    const moreId = "more:impact";
    if (hiddenAssets + hiddenServices > 0) {
      const parts = [hiddenServices && `${hiddenServices} services`, hiddenAssets && `${hiddenAssets} assets`].filter(Boolean);
      addNode({ id: moreId, kind: "more", label: `+${parts.join(", ")} more`, sublabel: "beyond the tool's 25-item lists",
                impacted: true, toolIds: [toolId] });
    }

    if (subgraph) {
      edgesKnown = true;
      const keyOf = new Map<string, string>();
      keyOf.set(`${subgraph.root.type}:${subgraph.root.id}`, rootId);
      subgraph.services.forEach((s) => keyOf.set(`Service:${s.id}`, serviceId(s.name)));
      subgraph.assets.forEach((a) => keyOf.set(`Asset:${a.id}`, assetId(a.tag)));
      const linkedToMore = new Set<string>();
      for (const e of subgraph.edges) {
        const dependency = keyOf.get(`${e.target.type}:${e.target.id}`);
        const dependent = keyOf.get(`${e.source.type}:${e.source.id}`);
        if (!dependency || !dependent) continue;
        const kind: EdgeKind = e.kind === "runs_on" ? "runs_on" : "depends_on";
        // Drawn in the direction the outage spreads: from the dependency to what depends on it. Only
        // shortest-path edges (one hop deeper) are drawn, so columns read as hop distance and the
        // graph stays legible at ~60 nodes; the other edges are counted.
        if (nodes.has(dependency) && nodes.has(dependent)) {
          const dd = nodes.get(dependency)!.depth ?? 0;
          const dt = nodes.get(dependent)!.depth ?? 0;
          if (dt === dd + 1) addEdge(dependency, dependent, kind);
          else crossEdges++;
        }
        else if (nodes.has(dependency) && nodes.has(moreId) && !linkedToMore.has(dependency)) {
          linkedToMore.add(dependency);
          addEdge(dependency, moreId, "more");
        }
      }
    } else {
      // Without the subgraph only direct dependents (depth 1) are known to hang off the root.
      for (const n of nodes.values()) if (n.depth === 1) addEdge(rootId, n.id, "depends_on");
    }
    if (nodes.has(moreId) && ![...edges.values()].some((e) => e.target === moreId)) addEdge(rootId, moreId, "more");

    const owners = new Map<string, string[]>();
    (data.services ?? []).forEach((s) => s.owner && owners.set(s.owner, [...(owners.get(s.owner) ?? []), serviceId(s.name)]));
    (data.assets ?? []).forEach((a) => a.custodian && owners.set(a.custodian, [...(owners.get(a.custodian) ?? []), assetId(a.tag)]));
    people = (data.people ?? []).map((p) => ({
      name: p.name,
      department: p.department,
      owns: (owners.get(p.name) ?? []).map((id) => nodes.get(id)?.label ?? id.replace(/^\w+:/, "")),
    }));
    if (showPeople) {
      for (const p of data.people ?? []) {
        const linked = (owners.get(p.name) ?? []).filter((id) => nodes.has(id));
        if (linked.length === 0 && !nodes.has(moreId)) continue;
        addNode({ id: personId(p.name), kind: "person", label: p.name, sublabel: p.department, impacted: true, toolIds: [toolId] });
        if (linked.length === 0) addEdge(moreId, personId(p.name), "more");
        for (const id of linked) addEdge(id, personId(p.name), nodes.get(id)?.kind === "service" ? "owns" : "custodian");
      }
    }
  }

  for (const t of touches) {
    // Without an impact graph, or for assets it does not contain, a node for the tool call anchors them.
    const needsToolNode = !impact || t.assets.some((a) => !nodes.has(assetId(a.tag)));
    const toolNode = needsToolNode ? `tool:${t.toolId}` : null;
    if (toolNode) {
      addNode({ id: toolNode, kind: "tool", label: t.name, sublabel: toolSublabel(t), toolIds: [t.toolId],
                status: t.status === "error" ? "error" : "ok" });
    }
    for (const a of t.assets) {
      const id = assetId(a.tag);
      const sublabel = [a.tag, a.category ?? a.status].filter(Boolean).join(" · ");
      let node = nodes.get(id);
      if (!node) {
        node = addNode({ id, kind: "asset", label: a.name ?? a.tag, sublabel, category: a.category });
        if (!node) continue;
      } else if (node.label === a.tag && a.name) {
        node.label = a.name;
        node.sublabel = sublabel;
      }
      if (!node.touchedBy.includes(t.name)) node.touchedBy.push(t.name);
      if (!node.toolIds.includes(t.toolId)) node.toolIds.push(t.toolId);
      if (t.status === "error") node.status = "error";
      if (toolNode) addEdge(toolNode, id, "touched");
    }
    for (const p of t.people) {
      const pid = personId(p.name);
      const pnode = addNode({ id: pid, kind: "person", label: p.name, sublabel: "checked out to" });
      if (pnode && !pnode.toolIds.includes(t.toolId)) pnode.toolIds.push(t.toolId);
      addEdge(assetId(p.tag), pid, "checked_out");
    }
  }

  return {
    nodes: [...nodes.values()],
    edges: [...edges.values()],
    source: impact ? "impact" : "tools",
    title,
    counts: impact?.data.counts,
    edgesKnown,
    crossEdges,
    people,
  };
}

function hop(depth: number) {
  return depth === 1 ? "direct" : `${depth} hops`;
}

function toolSublabel(t: ToolTouch) {
  const n = t.assets.length;
  return `${n} asset${n === 1 ? "" : "s"}${t.status === "error" ? " · error" : ""}`;
}
