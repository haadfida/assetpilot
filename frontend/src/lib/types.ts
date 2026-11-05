// Wire types for the AssetPilot agent API (see app/controllers/api/agent_runs_controller.rb).

export type RunMode = "live" | "replay";

export interface Usage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number;
  cache_creation_input_tokens: number;
}

export interface RunSummary {
  id: number;
  prompt: string;
  model: string;
  mode: RunMode;
  status: string;
  recorded: string | null;
  replay_slug: string | null;
  stream_url: string;
}

export interface Replay {
  slug: string;
  prompt: string;
  recorded: string;
}

export type ToolOutput =
  | { ok: true; data: Record<string, unknown> }
  | { ok: false; error: { code: string; message: string; details?: Record<string, unknown> } };

export interface ProgressEvent { type: "progress"; step: number; delta: string }
export interface TextEvent { type: "text"; step: number; delta: string }
export interface ToolCallEvent { type: "tool_call"; step: number; id: string; name: string; input: Record<string, unknown> }
export interface ToolResultEvent {
  type: "tool_result";
  step: number;
  tool_use_id: string;
  name: string;
  is_error: boolean;
  output: ToolOutput;
  duration_ms: number | null;
}
export interface ErrorEvent { type: "error"; step?: number; code: string; message: string }
export interface DoneEvent {
  type: "done";
  id: number;
  status: string;
  mode: RunMode;
  recorded: string | null;
  model: string;
  iterations: number;
  stop_reason: string | null;
  usage: Usage;
  duration_ms: number | null;
  steps: number;
}

export type AgentEvent = ProgressEvent | TextEvent | ToolCallEvent | ToolResultEvent | ErrorEvent | DoneEvent;
export type AgentEventType = AgentEvent["type"];

export const AGENT_EVENT_TYPES: readonly AgentEventType[] = ["progress", "text", "tool_call", "tool_result", "error", "done"];
