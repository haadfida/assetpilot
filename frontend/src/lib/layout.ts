// Left-to-right auto layout with dagre: the failing node on the left, the outage spreading right,
// people to notify in the last column. Falls back to hop-distance columns when edges are unknown.

import dagre from "@dagrejs/dagre";
import type { GraphModel, GraphNode } from "./graph";

export interface Positioned {
  id: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

export function nodeSize(n: GraphNode): { width: number; height: number } {
  if (n.kind === "person") return { width: 168, height: 38 };
  if (n.kind === "more") return { width: 184, height: 44 };
  if (n.root) return { width: 200, height: 52 };
  return { width: 196, height: 46 };
}

export function layoutGraph(model: GraphModel): Map<string, Positioned> {
  const out = new Map<string, Positioned>();
  if (model.nodes.length === 0) return out;

  if (model.source === "impact" && !model.edgesKnown) return layeredByDepth(model);

  const g = new dagre.graphlib.Graph();
  g.setGraph({ rankdir: "LR", ranksep: 56, nodesep: 8, edgesep: 4, marginx: 16, marginy: 16, ranker: "network-simplex" });
  g.setDefaultEdgeLabel(() => ({}));
  for (const n of model.nodes) g.setNode(n.id, nodeSize(n));
  for (const e of model.edges) g.setEdge(e.source, e.target, { weight: e.kind === "owns" || e.kind === "custodian" ? 2 : 1 });
  dagre.layout(g);

  for (const n of model.nodes) {
    const p = g.node(n.id);
    const { width, height } = nodeSize(n);
    out.set(n.id, { id: n.id, x: p.x - width / 2, y: p.y - height / 2, width, height });
  }
  return out;
}

function layeredByDepth(model: GraphModel): Map<string, Positioned> {
  const out = new Map<string, Positioned>();
  const columns = new Map<number, GraphNode[]>();
  const maxDepth = Math.max(0, ...model.nodes.map((n) => n.depth ?? 0));
  for (const n of model.nodes) {
    const col = n.kind === "person" ? maxDepth + 2 : n.kind === "more" || n.kind === "tool" ? maxDepth + 1 : (n.depth ?? 0);
    columns.set(col, [...(columns.get(col) ?? []), n]);
  }
  for (const [col, list] of columns) {
    let y = 16;
    for (const n of list) {
      const { width, height } = nodeSize(n);
      out.set(n.id, { id: n.id, x: 16 + col * 264, y, width, height });
      y += height + 10;
    }
  }
  return out;
}
