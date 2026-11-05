// One-line, human summaries of tool inputs and results for the tool-call cards.

import type { ToolOutput } from "./types";

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === "object" && v !== null && !Array.isArray(v);
const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

export function summarizeInput(input: Obj): string {
  const parts = Object.entries(input)
    .filter(([, v]) => v !== null && v !== undefined && v !== "")
    .map(([k, v]) => `${k}: ${Array.isArray(v) ? v.join(", ") : isObj(v) ? "{…}" : String(v)}`);
  return parts.length ? parts.join(" · ") : "no arguments";
}

export function summarizeResult(name: string, output: ToolOutput | undefined): string {
  if (!output) return "Running…";
  if (output.ok === false) return `${output.error.code}: ${output.error.message}`;
  const d = output.data;
  switch (name) {
    case "impact_analysis": {
      const c = d.counts as { services: number; assets: number; people: number } | undefined;
      return c ? `${plural(c.services, "service")}, ${plural(c.assets, "asset")}, ${plural(c.people, "person").replace("persons", "people")} affected` : "Impact computed";
    }
    case "search_assets": {
      const returned = Number(d.returned ?? 0);
      const total = Number(d.total ?? returned);
      return total > returned ? `${returned} of ${plural(total, "matching asset")}` : `${plural(total, "matching asset")}`;
    }
    case "get_asset":
      return [d.tag, d.name, d.status].filter(Boolean).join(" · ") || "Asset found";
    case "checkout_asset": {
      const a = isObj(d.asset) ? d.asset : {};
      const p = isObj(d.person) ? d.person : {};
      return `${a.tag ?? "Asset"} checked out to ${p.name ?? "?"}${d.due_at ? `, due ${formatDate(String(d.due_at))}` : ""}`;
    }
    case "checkin_asset": {
      const a = isObj(d.asset) ? d.asset : {};
      const late = d.returned_late ? ` · ${d.days_overdue} days late` : "";
      return `${a.tag ?? "Asset"} checked in${late}`;
    }
    case "schedule_maintenance": {
      const skipped = Array.isArray(d.skipped) ? d.skipped.length : 0;
      return `${plural(Number(d.scheduled_count ?? 0), "task")} scheduled${d.due_on ? ` for ${formatDate(String(d.due_on))}` : ""}${skipped ? `, ${skipped} skipped` : ""}`;
    }
    case "summarize_fleet":
      return `${d.total_assets ?? "?"} assets · ${d.scope ?? "fleet"}`;
    default:
      return "Done";
  }
}

export function formatDate(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

export function formatMs(ms: number | null | undefined): string {
  if (ms === null || ms === undefined) return "–";
  if (ms < 1000) return `${Math.round(ms)} ms`;
  return `${(ms / 1000).toFixed(ms < 10_000 ? 1 : 0)} s`;
}
