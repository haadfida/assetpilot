// HTTP client for the Rails API. In development requests go to /api on the Vite origin and are
// proxied; a production build calls VITE_API_URL (empty = same origin).

import { HttpError, readSSE, toAgentEvent } from "./sse";
import type { AgentEvent, Replay, RunSummary } from "./types";

const BASE = (import.meta.env.VITE_API_URL ?? "").replace(/\/+$/, "");
export const KEY_HEADER = "x-anthropic-key";

export const apiUrl = (path: string) => `${BASE}${path}`;

function headers(apiKey?: string | null, json = false): HeadersInit {
  const h: Record<string, string> = { accept: "application/json" };
  if (json) h["content-type"] = "application/json";
  if (apiKey) h[KEY_HEADER] = apiKey;
  return h;
}

async function errorFrom(res: Response): Promise<HttpError> {
  let code = `http_${res.status}`;
  let message = `${res.status} ${res.statusText}`.trim();
  try {
    const body = (await res.json()) as { error?: string; message?: string };
    if (body.error) code = body.error;
    if (body.message) message = body.message;
  } catch {
    // not JSON; keep the status line
  }
  return new HttpError(res.status, code, message);
}

async function getJSON<T>(path: string, signal?: AbortSignal): Promise<T> {
  const res = await fetch(apiUrl(path), { headers: headers(), signal });
  if (!res.ok) throw await errorFrom(res);
  return (await res.json()) as T;
}

export async function fetchReplays(signal?: AbortSignal): Promise<Replay[]> {
  return (await getJSON<{ data: Replay[] }>("/api/agent/replays", signal)).data;
}

export interface CreateRunParams {
  prompt: string;
  replay?: string;
  mode?: "replay";
  apiKey?: string | null;
}

export async function createRun({ prompt, replay, mode, apiKey }: CreateRunParams, signal?: AbortSignal): Promise<RunSummary> {
  const res = await fetch(apiUrl("/api/agent/runs"), {
    method: "POST",
    headers: headers(apiKey, true),
    body: JSON.stringify({ prompt, replay, mode }),
    signal,
  });
  if (!res.ok) throw await errorFrom(res);
  return ((await res.json()) as { data: RunSummary }).data;
}

/** Opens a run's SSE stream. The BYOK key must be sent here too: live runs execute on this request. */
export async function streamRun(
  streamUrl: string,
  { apiKey, speed, onEvent, signal }: { apiKey?: string | null; speed?: number; onEvent: (e: AgentEvent) => void; signal?: AbortSignal },
): Promise<void> {
  const url = new URL(apiUrl(streamUrl), window.location.href);
  if (speed) url.searchParams.set("speed", String(speed));
  const res = await fetch(url, {
    headers: { ...headers(apiKey), accept: "text/event-stream" },
    signal,
    cache: "no-store",
  });
  if (!res.ok) throw await errorFrom(res);
  await readSSE(res, (msg) => {
    const event = toAgentEvent(msg);
    if (event) onEvent(event);
  });
}

// --- dependency subgraph -----------------------------------------------------------------------

export interface SubgraphNodeRef { type: "Asset" | "Service"; id: number }
export interface Subgraph {
  root: { type: "Asset" | "Service"; id: number; name: string };
  services: { id: number; name: string; criticality: string; owner_id: number | null; depth: number }[];
  assets: { id: number; tag: string; name: string; category: string; status: string; custodian_id: number | null; depth: number }[];
  people: { id: number; name: string; email: string; department: string }[];
  edges: { source: SubgraphNodeRef; target: SubgraphNodeRef; kind: string }[];
}

interface Paged<T> { data: T[] }

/** Resolves an impact_analysis root (asset tag/name or service name) to its id, then loads the subgraph. */
export async function fetchSubgraph(
  root: { type: "asset" | "service"; name: string; tag?: string },
  signal?: AbortSignal,
): Promise<Subgraph | null> {
  let id: number | undefined;
  if (root.type === "asset") {
    const q = encodeURIComponent(root.tag ?? root.name);
    const page = await getJSON<Paged<{ id: number; tag: string; name: string }>>(`/api/assets?q=${q}&per_page=10`, signal);
    id = page.data.find((a) => a.tag === root.tag || a.name === root.name)?.id;
  } else {
    const page = await getJSON<Paged<{ id: number; name: string }>>("/api/services?per_page=100", signal);
    id = page.data.find((s) => s.name === root.name)?.id;
  }
  if (id === undefined) return null;
  return getJSON<Subgraph>(`/api/impact/${root.type}/${id}`, signal);
}
