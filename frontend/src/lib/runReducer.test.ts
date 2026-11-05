import { describe, expect, it } from "vitest";
import { answerText, initialSession, isBusy, sessionReducer, type SessionAction, type SessionState, type ToolBlock } from "./runReducer";
import type { AgentEvent, RunSummary } from "./types";

const summary: RunSummary = {
  id: 3,
  prompt: "Check out AP-00016 to Marguerite Little",
  model: "claude-opus-5-5",
  mode: "replay",
  status: "queued",
  recorded: "synthetic",
  replay_slug: "checkout-conflict-ap-00016",
  stream_url: "/api/agent/runs/3/stream",
};

const done: AgentEvent = {
  type: "done",
  id: 3,
  status: "succeeded",
  mode: "replay",
  recorded: "synthetic",
  model: "claude-opus-5-5",
  iterations: 2,
  stop_reason: "end_turn",
  usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 },
  duration_ms: 861,
  steps: 7,
};

const reduce = (actions: SessionAction[], state: SessionState = initialSession) => actions.reduce(sessionReducer, state);
const ev = (event: AgentEvent): SessionAction => ({ type: "event", key: "r1", event });
const started: SessionAction[] = [
  { type: "start", key: "r1", prompt: "check out AP-00016", mode: "replay", replaySlug: "checkout-conflict-ap-00016" },
  { type: "created", key: "r1", run: summary },
];

describe("sessionReducer", () => {
  it("starts a run in the creating phase and moves to streaming once created", () => {
    const s1 = reduce(started.slice(0, 1));
    expect(s1.runs[0]).toMatchObject({ phase: "creating", mode: "replay", blocks: [] });
    expect(isBusy(s1)).toBe(true);
    const s2 = reduce(started);
    expect(s2.runs[0]).toMatchObject({ phase: "streaming", runId: 3, prompt: summary.prompt, recorded: "synthetic" });
  });

  it("merges consecutive deltas of the same step and kind", () => {
    const s = reduce([
      ...started,
      ev({ type: "progress", step: 0, delta: "Checking out " }),
      ev({ type: "progress", step: 0, delta: "AP-00016." }),
      ev({ type: "text", step: 6, delta: "I couldn't " }),
      ev({ type: "text", step: 6, delta: "check it out." }),
    ]);
    expect(s.runs[0].blocks.map((b) => [b.kind, "text" in b ? b.text : ""])).toEqual([
      ["progress", "Checking out AP-00016."],
      ["text", "I couldn't check it out."],
    ]);
    expect(answerText(s.runs[0])).toBe("I couldn't check it out.");
  });

  it("starts a new block when the step changes", () => {
    const s = reduce([...started, ev({ type: "progress", step: 0, delta: "a" }), ev({ type: "progress", step: 3, delta: "b" })]);
    expect(s.runs[0].blocks).toHaveLength(2);
  });

  it("pairs tool results with their calls and records status and duration", () => {
    const s = reduce([
      ...started,
      ev({ type: "tool_call", step: 1, id: "t1", name: "checkout_asset", input: { asset: "AP-00016" } }),
      ev({ type: "tool_call", step: 4, id: "t2", name: "search_assets", input: { query: "ThinkPad" } }),
      ev({
        type: "tool_result",
        step: 2,
        tool_use_id: "t1",
        name: "checkout_asset",
        is_error: true,
        output: { ok: false, error: { code: "already_checked_out", message: "AP-00016 is already checked out" } },
        duration_ms: 12,
      }),
    ]);
    const [t1, t2] = s.runs[0].blocks as ToolBlock[];
    expect(t1).toMatchObject({ id: "t1", status: "error", durationMs: 12 });
    expect(t2).toMatchObject({ id: "t2", status: "running" });
  });

  it("treats ok:false output as an error even without is_error", () => {
    const s = reduce([
      ...started,
      ev({ type: "tool_call", step: 1, id: "t1", name: "get_asset", input: {} }),
      ev({ type: "tool_result", step: 2, tool_use_id: "t1", name: "get_asset", is_error: false, output: { ok: false, error: { code: "not_found", message: "x" } }, duration_ms: 1 }),
    ]);
    expect((s.runs[0].blocks[0] as ToolBlock).status).toBe("error");
  });

  it("ignores a duplicate tool_call and keeps an orphan tool_result", () => {
    const s = reduce([
      ...started,
      ev({ type: "tool_call", step: 1, id: "t1", name: "get_asset", input: {} }),
      ev({ type: "tool_call", step: 1, id: "t1", name: "get_asset", input: {} }),
      ev({ type: "tool_result", step: 9, tool_use_id: "zz", name: "get_asset", is_error: false, output: { ok: true, data: {} }, duration_ms: 3 }),
    ]);
    expect(s.runs[0].blocks.map((b) => (b as ToolBlock).id)).toEqual(["t1", "zz"]);
  });

  it("finishes on done, closing calls that never got a result, and ignores later events", () => {
    const s = reduce([
      ...started,
      ev({ type: "tool_call", step: 1, id: "t1", name: "get_asset", input: {} }),
      ev(done),
      ev({ type: "text", step: 9, delta: "late" }),
      { type: "stream_ended", key: "r1" },
    ]);
    const run = s.runs[0];
    expect(run.phase).toBe("done");
    expect(run.done?.duration_ms).toBe(861);
    expect((run.blocks[0] as ToolBlock).status).toBe("error");
    expect(run.blocks).toHaveLength(1);
    expect(isBusy(s)).toBe(false);
  });

  it("records error events as blocks without ending the run", () => {
    const s = reduce([...started, ev({ type: "error", step: 2, code: "iteration_cap", message: "Stopped after 8 tool turns" })]);
    expect(s.runs[0].phase).toBe("streaming");
    expect(s.runs[0].blocks[0]).toMatchObject({ kind: "error", code: "iteration_cap" });
  });

  it("fails a run whose stream closes before done", () => {
    const s = reduce([...started, ev({ type: "text", step: 1, delta: "Hal" }), { type: "stream_ended", key: "r1" }]);
    expect(s.runs[0].phase).toBe("failed");
    expect(s.runs[0].blocks.at(-1)).toMatchObject({ kind: "error", code: "stream_ended" });
  });

  it("fails a run on an HTTP or network error", () => {
    const s = reduce([started[0], { type: "failed", key: "r1", code: "unknown_replay", message: "No API key was sent" }]);
    expect(s.runs[0]).toMatchObject({ phase: "failed" });
    expect(s.runs[0].blocks[0]).toMatchObject({ code: "unknown_replay" });
  });

  it("keeps runs independent and ignores actions for unknown runs", () => {
    const s = reduce([
      ...started,
      { type: "start", key: "r2", prompt: "Summarize the fleet", mode: "replay" },
      { type: "event", key: "r2", event: { type: "text", step: 1, delta: "506 assets" } },
      { type: "event", key: "nope", event: { type: "text", step: 1, delta: "x" } },
    ]);
    expect(s.runs).toHaveLength(2);
    expect(s.runs[0].blocks).toHaveLength(0);
    expect(answerText(s.runs[1])).toBe("506 assets");
    expect(sessionReducer(s, { type: "clear" })).toEqual(initialSession);
  });
});
