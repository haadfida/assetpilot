// Session state: the runs asked in this tab, each folded from its stream of agent events.
// Pure, so it is unit-tested event by event (src/lib/runReducer.test.ts).

import type { AgentEvent, DoneEvent, RunMode, RunSummary, ToolOutput } from "./types";

export interface NoteBlock {
  kind: "progress" | "text";
  key: string;
  step: number;
  text: string;
}

export interface ToolBlock {
  kind: "tool";
  key: string;
  id: string;
  step: number;
  name: string;
  input: Record<string, unknown>;
  status: "running" | "ok" | "error";
  output?: ToolOutput;
  durationMs?: number | null;
}

export interface ErrorBlock {
  kind: "error";
  key: string;
  code: string;
  message: string;
}

export type Block = NoteBlock | ToolBlock | ErrorBlock;

export type RunPhase = "creating" | "streaming" | "done" | "failed";

export interface Run {
  key: string;
  prompt: string;
  mode: RunMode;
  replaySlug?: string;
  recorded?: string | null;
  runId?: number;
  model?: string;
  phase: RunPhase;
  blocks: Block[];
  done?: DoneEvent;
}

export interface SessionState {
  runs: Run[];
}

export type SessionAction =
  | { type: "start"; key: string; prompt: string; mode: RunMode; replaySlug?: string }
  | { type: "created"; key: string; run: RunSummary }
  | { type: "event"; key: string; event: AgentEvent }
  | { type: "stream_ended"; key: string }
  | { type: "failed"; key: string; code: string; message: string }
  | { type: "clear" };

export const initialSession: SessionState = { runs: [] };

export function sessionReducer(state: SessionState, action: SessionAction): SessionState {
  switch (action.type) {
    case "clear":
      return initialSession;
    case "start":
      return {
        runs: [
          ...state.runs,
          { key: action.key, prompt: action.prompt, mode: action.mode, replaySlug: action.replaySlug, phase: "creating", blocks: [] },
        ],
      };
    default:
      return updateRun(state, action.key, (run) => runReducer(run, action));
  }
}

function updateRun(state: SessionState, key: string, fn: (run: Run) => Run): SessionState {
  const i = state.runs.findIndex((r) => r.key === key);
  if (i === -1) return state;
  const next = fn(state.runs[i]);
  if (next === state.runs[i]) return state;
  const runs = state.runs.slice();
  runs[i] = next;
  return { runs };
}

export function runReducer(run: Run, action: SessionAction): Run {
  switch (action.type) {
    case "created":
      return {
        ...run,
        runId: action.run.id,
        prompt: action.run.prompt,
        mode: action.run.mode,
        recorded: action.run.recorded,
        model: action.run.model,
        replaySlug: action.run.replay_slug ?? run.replaySlug,
        phase: "streaming",
      };
    case "event":
      return applyEvent(run, action.event);
    case "stream_ended":
      if (run.phase === "done" || run.phase === "failed") return run;
      return {
        ...run,
        phase: "failed",
        blocks: [...run.blocks, errorBlock(run, "stream_ended", "The stream closed before the run finished.")],
      };
    case "failed":
      if (run.phase === "done") return run;
      return { ...run, phase: "failed", blocks: [...run.blocks, errorBlock(run, action.code, action.message)] };
    default:
      return run;
  }
}

export function applyEvent(run: Run, event: AgentEvent): Run {
  if (run.phase === "done" || run.phase === "failed") return run;
  const base: Run = run.phase === "creating" ? { ...run, phase: "streaming" } : run;

  switch (event.type) {
    case "progress":
    case "text": {
      if (!event.delta) return base;
      const blocks = base.blocks;
      const last = blocks[blocks.length - 1];
      if (last && last.kind === event.type && last.step === event.step) {
        const merged: NoteBlock = { ...last, text: last.text + event.delta };
        return { ...base, blocks: [...blocks.slice(0, -1), merged] };
      }
      const block: NoteBlock = { kind: event.type, key: `${event.type}-${event.step}-${blocks.length}`, step: event.step, text: event.delta };
      return { ...base, blocks: [...blocks, block] };
    }
    case "tool_call": {
      if (base.blocks.some((b) => b.kind === "tool" && b.id === event.id)) return base;
      const block: ToolBlock = {
        kind: "tool",
        key: `tool-${event.id}`,
        id: event.id,
        step: event.step,
        name: event.name,
        input: event.input ?? {},
        status: "running",
      };
      return { ...base, blocks: [...base.blocks, block] };
    }
    case "tool_result": {
      const status = event.is_error || event.output?.ok === false ? "error" : "ok";
      const i = base.blocks.findIndex((b) => b.kind === "tool" && b.id === event.tool_use_id);
      if (i === -1) {
        // A result without its call (should not happen); keep it visible rather than drop it.
        const block: ToolBlock = {
          kind: "tool",
          key: `tool-${event.tool_use_id}`,
          id: event.tool_use_id,
          step: event.step,
          name: event.name,
          input: {},
          status,
          output: event.output,
          durationMs: event.duration_ms,
        };
        return { ...base, blocks: [...base.blocks, block] };
      }
      const blocks = base.blocks.slice();
      blocks[i] = { ...(blocks[i] as ToolBlock), status, output: event.output, durationMs: event.duration_ms };
      return { ...base, blocks };
    }
    case "error":
      return { ...base, blocks: [...base.blocks, errorBlock(base, event.code, event.message)] };
    case "done": {
      // Tool calls still marked running when the run ends never got a result.
      const blocks = base.blocks.map((b) => (b.kind === "tool" && b.status === "running" ? { ...b, status: "error" as const } : b));
      return { ...base, blocks, phase: "done", done: event, recorded: event.recorded, model: event.model, mode: event.mode };
    }
    default:
      return base;
  }
}

function errorBlock(run: Run, code: string, message: string): ErrorBlock {
  return { kind: "error", key: `error-${run.blocks.length}`, code, message };
}

/** True while a run in the session is still being created or streamed. */
export const isBusy = (state: SessionState) => state.runs.some((r) => r.phase === "creating" || r.phase === "streaming");

/** The final answer text of a run (all text blocks joined). */
export const answerText = (run: Run) =>
  run.blocks.filter((b): b is NoteBlock => b.kind === "text").map((b) => b.text).join("");
