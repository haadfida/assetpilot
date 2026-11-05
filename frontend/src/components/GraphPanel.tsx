import { memo, useEffect, useMemo, useState } from "react";
import {
  Background,
  Controls,
  Handle,
  MarkerType,
  Position,
  ReactFlow,
  ReactFlowProvider,
  useReactFlow,
  type Edge,
  type Node,
  type NodeProps,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import { fetchSubgraph, type Subgraph } from "../lib/api";
import { buildGraph, collectTouches, findImpact, type GraphEdge, type GraphModel, type GraphNode } from "../lib/graph";
import { layoutGraph } from "../lib/layout";
import type { Run } from "../lib/runReducer";
import { Graph as GraphIcon, Spinner } from "./icons";

interface Props {
  run: Run | undefined;
  focusedTool: string | null;
  onTryPrompt: () => void;
  canTry: boolean;
}

type SubgraphState = { key: string; status: "loading" | "ready" | "failed"; data: Subgraph | null };

export default function GraphPanel(props: Props) {
  return (
    <ReactFlowProvider>
      <GraphPanelInner {...props} />
    </ReactFlowProvider>
  );
}

function GraphPanelInner({ run, focusedTool, onTryPrompt, canTry }: Props) {
  const [showPeople, setShowPeople] = useState(false);
  const [sub, setSub] = useState<SubgraphState | null>(null);

  const impact = useMemo(() => findImpact(run), [run]);
  const touches = useMemo(() => collectTouches(run), [run]);
  const impactKey = impact ? `${run?.key}:${impact.toolId}` : null;

  // Load the dependency edges for an impact result once per tool call.
  useEffect(() => {
    if (!impact || !impactKey) return;
    const ctrl = new AbortController();
    const { root } = impact.data;
    Promise.resolve().then(() => setSub({ key: impactKey, status: "loading", data: null }));
    fetchSubgraph({ type: root.type, name: root.name, tag: root.tag }, ctrl.signal)
      .then((data) => setSub({ key: impactKey, status: data ? "ready" : "failed", data }))
      .catch(() => !ctrl.signal.aborted && setSub({ key: impactKey, status: "failed", data: null }));
    return () => ctrl.abort();
    // impactKey identifies the impact result
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [impactKey]);

  const subState = impactKey && sub?.key === impactKey ? sub : null;
  const loadingEdges = !!impact && (!subState || subState.status === "loading");

  const model = useMemo(
    () => (loadingEdges ? null : buildGraph(impact, subState?.data ?? null, touches, { showPeople })),
    [impact, subState, touches, showPeople, loadingEdges],
  );

  return (
    <section aria-label="Dependency graph" className="relative flex min-h-[460px] flex-col border-l border-line bg-surface lg:min-h-0">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2 border-b border-line px-4 py-2.5">
        <div className="min-w-0">
          <h2 className="truncate text-[14px] font-semibold tracking-tight">{model?.title ?? "Dependency graph"}</h2>
          <p className="truncate text-[12px] text-muted">
            {run && model ? `From: ${run.prompt}` : "Services, assets and people the agent's tools touch"}
          </p>
        </div>
        {model?.counts && (
          <dl className="ml-auto flex items-center gap-3 text-[12px]">
            <Count label="services" value={model.counts.services} color="bg-node-service" />
            <Count label="assets" value={model.counts.assets} color="bg-node-asset" />
            <Count label="people" value={model.counts.people} color="bg-node-person" />
          </dl>
        )}
        {model?.source === "impact" && (
          <label className="flex cursor-pointer items-center gap-2 text-[12.5px] text-ink-2 select-none">
            <input
              type="checkbox"
              checked={showPeople}
              onChange={(e) => setShowPeople(e.target.checked)}
              className="size-3.5 accent-[var(--color-brand)]"
            />
            Draw people
          </label>
        )}
      </div>

      <div className="relative min-h-0 flex-1">
        {model ? (
          <FlowCanvas model={model} focusedTool={focusedTool} />
        ) : loadingEdges ? (
          <div className="grid h-full place-items-center text-sm text-muted">
            <span className="inline-flex items-center gap-2">
              <Spinner className="size-4 text-brand" /> Resolving dependency edges…
            </span>
          </div>
        ) : (
          <EmptyGraph run={run} onTryPrompt={onTryPrompt} canTry={canTry} />
        )}
        {model && <Legend model={model} />}
        {model && model.people.length > 0 && <PeopleList model={model} />}
        {model?.source === "impact" && !model.edgesKnown && (
          <p className="absolute top-3 left-1/2 -translate-x-1/2 rounded-md border border-warn/25 bg-warn-soft px-2 py-1 text-[11.5px] text-warn">
            Dependency edges unavailable: nodes are laid out by hop distance.
          </p>
        )}
      </div>
    </section>
  );
}

function Count({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="flex items-center gap-1.5">
      <span className={`size-2 rounded-full ${color}`} aria-hidden />
      <dt className="sr-only">{label}</dt>
      <dd>
        <span className="font-semibold text-ink tabular-nums">{value}</span> <span className="text-muted">{label}</span>
      </dd>
    </div>
  );
}

function EmptyGraph({ run, onTryPrompt, canTry }: { run: Run | undefined; onTryPrompt: () => void; canTry: boolean }) {
  return (
    <div className="grid h-full place-items-center p-8">
      <div className="max-w-[360px] text-center">
        <div className="mx-auto grid size-12 place-items-center rounded-2xl bg-brand-soft text-brand">
          <GraphIcon className="size-6" />
        </div>
        <h3 className="mt-4 text-[15px] font-semibold">{run ? "No assets touched yet" : "The blast radius draws here"}</h3>
        <p className="mt-1.5 text-[13.5px] leading-relaxed text-muted">
          {run
            ? "This answer didn't touch specific assets. Impact questions draw the dependency graph; searches and check-outs highlight the assets they touch."
            : "When the agent runs an impact analysis, the impacted services, assets and the people to notify appear here, laid out from the failing node outward."}
        </p>
        {canTry && (
          <button
            type="button"
            onClick={onTryPrompt}
            className="mt-4 rounded-lg border border-line px-3 py-1.5 text-[13px] font-medium text-ink-2 hover:border-brand/40 hover:bg-brand-soft hover:text-brand-ink"
          >
            Try “What breaks if DB-Server goes down?”
          </button>
        )}
      </div>
    </div>
  );
}

function PeopleList({ model }: { model: GraphModel }) {
  const [open, setOpen] = useState(false);
  const total = model.counts?.people ?? model.people.length;
  return (
    <div className="absolute top-3 left-3 w-[250px] overflow-hidden rounded-lg border border-line bg-surface/95 shadow-sm backdrop-blur">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="flex w-full items-center gap-2 px-3 py-2 text-left text-[12px] font-semibold text-ink"
      >
        <span className="size-2 rounded-full bg-node-person" aria-hidden />
        People to notify
        <span className="font-normal text-muted">
          {model.people.length < total ? `${model.people.length} of ${total}` : total}
        </span>
        <span className="ml-auto text-[11px] font-medium text-brand">{open ? "Hide" : "Show"}</span>
      </button>
      {open && (
        <ul className="max-h-[320px] overflow-y-auto border-t border-line px-3 py-1.5 text-[12px]">
          {model.people.map((p) => (
            <li key={p.name} className="py-1">
              <span className="font-medium text-ink">{p.name}</span> <span className="text-muted">· {p.department}</span>
              {p.owns.length > 0 && <div className="truncate text-[11px] text-muted">{p.owns.join(", ")}</div>}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Legend({ model }: { model: GraphModel }) {
  const touched = model.nodes.some((n) => n.touchedBy.length > 0);
  return (
    <div className="pointer-events-none absolute right-3 bottom-3 flex flex-wrap items-center justify-end gap-x-3 gap-y-1 rounded-lg border border-line bg-surface/90 px-2.5 py-1.5 text-[11px] text-ink-2 shadow-sm backdrop-blur">
      {model.source === "impact" && (
        <span className="inline-flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm bg-bad" /> failing
        </span>
      )}
      <span className="inline-flex items-center gap-1.5">
        <span className="size-2.5 rounded-sm bg-node-service" /> service
      </span>
      <span className="inline-flex items-center gap-1.5">
        <span className="size-2.5 rounded-sm bg-node-asset" /> asset
      </span>
      <span className="inline-flex items-center gap-1.5">
        <span className="size-2.5 rounded-full bg-node-person" /> person
      </span>
      {model.crossEdges > 0 && <span className="text-muted">shortest paths · {model.crossEdges} more links hidden</span>}
      {touched && (
        <span className="inline-flex items-center gap-1.5">
          <span className="size-2.5 rounded-sm ring-2 ring-ok" /> touched by a tool
        </span>
      )}
    </div>
  );
}

// --- canvas ------------------------------------------------------------------------------------

type FlowNodeData = { node: GraphNode; dim: boolean; lit: boolean };
type FlowNode = Node<FlowNodeData, "entity">;

const nodeTypes = { entity: memo(EntityNode) };

function FlowCanvas({ model, focusedTool }: { model: GraphModel; focusedTool: string | null }) {
  const positions = useMemo(() => layoutGraph(model), [model]);
  const { fitView } = useReactFlow();

  const nodes: FlowNode[] = useMemo(
    () =>
      model.nodes.map((n) => {
        const p = positions.get(n.id)!;
        const lit = !!focusedTool && n.toolIds.includes(focusedTool);
        return {
          id: n.id,
          type: "entity",
          position: { x: p.x, y: p.y },
          width: p.width,
          height: p.height,
          data: { node: n, lit, dim: !!focusedTool && !lit },
          draggable: false,
          connectable: false,
        };
      }),
    [model, positions, focusedTool],
  );

  const litIds = useMemo(() => new Set(nodes.filter((n) => n.data.lit).map((n) => n.id)), [nodes]);
  const edges: Edge[] = useMemo(() => model.edges.map((e) => toFlowEdge(e, focusedTool ? litIds : null)), [model, focusedTool, litIds]);

  // Re-fit whenever the graph itself changes (a new tool result), not on focus changes.
  useEffect(() => {
    const id = requestAnimationFrame(() => fitView({ padding: 0.12, duration: 300, maxZoom: 1.1 }));
    return () => cancelAnimationFrame(id);
  }, [model, fitView]);

  return (
    <ReactFlow
      nodes={nodes}
      edges={edges}
      nodeTypes={nodeTypes}
      fitView
      fitViewOptions={{ padding: 0.12, maxZoom: 1.1 }}
      minZoom={0.2}
      maxZoom={2}
      nodesDraggable={false}
      nodesConnectable={false}
      elementsSelectable={false}
      proOptions={{ hideAttribution: false }}
      aria-label="Dependency graph canvas"
    >
      <Background gap={20} size={1} color="#dde1e7" />
      <Controls showInteractive={false} position="top-right" />
    </ReactFlow>
  );
}

const EDGE_STYLE: Record<GraphEdge["kind"], { stroke: string; dash?: string; width: number }> = {
  depends_on: { stroke: "#a9b1be", width: 1.2 },
  runs_on: { stroke: "#5d6778", width: 1.6 },
  owns: { stroke: "#d7b37a", dash: "3 3", width: 1.1 },
  custodian: { stroke: "#d7b37a", dash: "3 3", width: 1.1 },
  checked_out: { stroke: "#a65f00", width: 1.4 },
  touched: { stroke: "#0f8a5f", width: 1.4 },
  more: { stroke: "#c3c9d3", dash: "4 4", width: 1 },
};

function toFlowEdge(e: GraphEdge, lit: Set<string> | null): Edge {
  const s = EDGE_STYLE[e.kind];
  const on = lit ? lit.has(e.source) && lit.has(e.target) : false;
  return {
    id: e.id,
    source: e.source,
    target: e.target,
    type: "default",
    animated: e.kind === "touched",
    markerEnd: { type: MarkerType.ArrowClosed, width: 14, height: 14, color: on ? "#3949d6" : s.stroke },
    style: {
      stroke: on ? "#3949d6" : s.stroke,
      strokeWidth: on ? s.width + 0.8 : s.width,
      strokeDasharray: s.dash,
      opacity: lit && !on ? 0.25 : 1,
    },
  };
}

const CRIT: Record<string, string> = {
  critical: "bg-crit-critical",
  high: "bg-crit-high",
  medium: "bg-crit-medium",
  low: "bg-crit-low",
};

function EntityNode({ data }: NodeProps<FlowNode>) {
  const { node: n, dim, lit } = data;
  const touched = n.touchedBy.length > 0;
  const title = [n.label, n.sublabel, touched ? `touched by ${n.touchedBy.join(", ")}` : null].filter(Boolean).join(" · ");

  let shell = "rounded-lg border bg-surface";
  let accent = "";
  if (n.root) {
    shell = "rounded-lg border border-bad/50 bg-bad-soft";
    accent = "bg-bad";
  } else if (n.kind === "service") accent = "bg-node-service";
  else if (n.kind === "asset") accent = "bg-node-asset";
  else if (n.kind === "person") shell = "rounded-full border border-node-person/30 bg-warn-soft";
  else if (n.kind === "tool") shell = `rounded-lg border ${n.status === "error" ? "border-bad bg-bad" : "border-ink bg-ink"} text-white`;
  else if (n.kind === "more") shell = "rounded-lg border border-dashed border-line-strong bg-canvas";

  const ring = lit ? "ring-2 ring-brand shadow-lg" : touched ? (n.status === "error" ? "ring-2 ring-bad" : "ring-2 ring-ok") : "";

  return (
    <div
      title={title}
      className={`node-in relative flex h-full w-full items-center gap-2 overflow-hidden ${shell} ${ring} ${
        n.kind === "person" ? "px-3" : "pr-2.5 pl-3"
      } shadow-[0_1px_2px_rgb(14_23_38/0.06)] transition-opacity ${dim ? "opacity-30" : "opacity-100"} ${
        n.kind === "tool" || n.kind === "person" ? "" : "border-line"
      }`}
    >
      <Handle type="target" position={Position.Left} className="size-1.5! min-h-0! min-w-0! border-0! bg-line-strong!" />
      {accent && <span className={`absolute inset-y-0 left-0 w-1 ${accent}`} aria-hidden />}
      <div className="min-w-0 flex-1 leading-tight">
        <div className={`truncate font-medium ${n.root ? "text-[13px] text-bad" : n.kind === "tool" ? "font-mono text-[12px]" : "text-[12.5px] text-ink"}`}>
          {n.root && <span className="mr-1 text-[10px] font-bold tracking-wider uppercase">Down ·</span>}
          {n.label}
        </div>
        {n.sublabel && (
          <div className={`mt-0.5 truncate text-[10.5px] ${n.kind === "tool" ? "text-white/70" : "text-muted"}`}>{n.sublabel}</div>
        )}
      </div>
      {n.criticality && !n.root && <span className={`size-2 shrink-0 rounded-full ${CRIT[n.criticality] ?? "bg-crit-low"}`} title={`${n.criticality} criticality`} />}
      {touched && n.kind !== "tool" && (
        <span className="shrink-0 rounded bg-ok-soft px-1 py-px font-mono text-[9.5px] font-medium text-ok">{shortTool(n.touchedBy)}</span>
      )}
      <Handle type="source" position={Position.Right} className="size-1.5! min-h-0! min-w-0! border-0! bg-line-strong!" />
    </div>
  );
}

const SHORT: Record<string, string> = {
  search_assets: "search",
  get_asset: "get",
  checkout_asset: "checkout",
  checkin_asset: "checkin",
  schedule_maintenance: "maint.",
};

function shortTool(names: string[]) {
  const last = names[names.length - 1];
  const n = SHORT[last] ?? last;
  return names.length > 1 ? `${n} +${names.length - 1}` : n;
}
