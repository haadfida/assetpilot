import { memo, useState } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { Block, NoteBlock, Run, ToolBlock } from "../lib/runReducer";
import { formatMs, summarizeInput, summarizeResult } from "../lib/toolSummary";
import { Check, Chevron, Cross, Info, Sparkle, Spinner, Wrench } from "./icons";

interface Props {
  run: Run;
  focusedTool: string | null;
  onFocusTool: (id: string | null) => void;
}

export const RunView = memo(function RunView({ run, focusedTool, onFocusTool }: Props) {
  const streaming = run.phase === "creating" || run.phase === "streaming";
  const lastText = [...run.blocks].reverse().find((b) => b.kind === "text");
  const synthetic = run.mode === "replay" && (run.recorded ?? "synthetic") === "synthetic";

  return (
    <article className="space-y-3" aria-busy={streaming}>
      <div className="flex justify-end">
        <p className="max-w-[85%] rounded-2xl rounded-br-md bg-ink px-4 py-2.5 text-[14.5px] leading-relaxed text-white">{run.prompt}</p>
      </div>

      <div className="rounded-2xl border border-line bg-surface shadow-[0_1px_2px_rgb(14_23_38/0.04)]">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 border-b border-line px-4 py-2.5 text-xs text-muted">
          <span className="font-semibold text-ink">AssetPilot</span>
          {run.mode === "replay" ? (
            <span className="rounded-full bg-warn-soft px-2 py-0.5 font-medium text-warn">Replay · synthetic</span>
          ) : (
            <span className="rounded-full bg-ok-soft px-2 py-0.5 font-medium text-ok">Live</span>
          )}
          {run.model && <span className="font-mono">{run.model}</span>}
          {streaming && (
            <span className="ml-auto inline-flex items-center gap-1 text-brand">
              <Spinner className="size-3.5" /> {run.phase === "creating" ? "Starting" : "Streaming"}
            </span>
          )}
        </div>

        {synthetic && <SyntheticNotice />}

        <div className="space-y-2.5 px-4 py-3.5">
          {run.blocks.length === 0 && streaming && <p className="text-sm text-muted">Connecting to the agent…</p>}
          {run.blocks.map((b) => (
            <BlockView
              key={b.key}
              block={b}
              caret={streaming && b === lastText}
              focused={b.kind === "tool" && focusedTool === b.id}
              onFocusTool={onFocusTool}
            />
          ))}
        </div>

        {run.done && <DoneFooter run={run} />}
      </div>
    </article>
  );
});

function SyntheticNotice() {
  return (
    <div className="flex gap-2 border-b border-warn/15 bg-warn-soft/60 px-4 py-2.5 text-[12.5px] leading-relaxed text-ink-2">
      <Info className="mt-0.5 size-3.5 shrink-0 text-warn" />
      <p>
        <span className="font-semibold text-warn">Synthetic recording.</span> The tool calls and their results are real: they were
        executed against the seeded inventory. The prose is templated over those results, not written by a model, and timings
        and token counts are estimates. Add your key for a live run.
      </p>
    </div>
  );
}

function BlockView({
  block,
  caret,
  focused,
  onFocusTool,
}: {
  block: Block;
  caret: boolean;
  focused: boolean;
  onFocusTool: (id: string | null) => void;
}) {
  switch (block.kind) {
    case "text":
      return (
        <div className={`prose-answer ${caret ? "streaming-caret" : ""}`}>
          <Markdown remarkPlugins={[remarkGfm]}>{block.text}</Markdown>
        </div>
      );
    case "progress":
      return <ProgressNote block={block} />;
    case "tool":
      return <ToolCard block={block} focused={focused} onFocusTool={onFocusTool} />;
    case "error":
      return (
        <div role="alert" className="rounded-lg border border-bad/25 bg-bad-soft px-3 py-2 text-[13px] text-bad">
          <span className="font-mono font-medium">{block.code}</span> · {block.message}
        </div>
      );
  }
}

function ProgressNote({ block }: { block: NoteBlock }) {
  const [open, setOpen] = useState(false);
  return (
    <button
      type="button"
      onClick={() => setOpen((o) => !o)}
      aria-expanded={open}
      className="group flex w-full items-start gap-2 rounded-md text-left text-[13px] text-muted hover:text-ink-2"
    >
      <Sparkle className="mt-0.5 size-3.5 shrink-0 text-faint" />
      <span className={open ? "" : "line-clamp-1"}>
        <span className="sr-only">Progress note: </span>
        {block.text}
      </span>
      <Chevron className={`mt-0.5 ml-auto size-3.5 shrink-0 text-faint transition-transform ${open ? "rotate-90" : ""}`} />
    </button>
  );
}

function ToolCard({ block, focused, onFocusTool }: { block: ToolBlock; focused: boolean; onFocusTool: (id: string | null) => void }) {
  const [open, setOpen] = useState(false);
  const [raw, setRaw] = useState(false);
  const statusIcon =
    block.status === "running" ? (
      <Spinner className="size-3.5 text-brand" />
    ) : block.status === "ok" ? (
      <Check className="size-3.5 text-ok" />
    ) : (
      <Cross className="size-3.5 text-bad" />
    );
  const summary = summarizeResult(block.name, block.output);

  return (
    <div
      className={`rounded-xl border transition-colors ${
        focused ? "border-brand/50 ring-2 ring-brand/15" : block.status === "error" ? "border-bad/30" : "border-line"
      } bg-canvas/60`}
      onMouseEnter={() => onFocusTool(block.id)}
      onMouseLeave={() => onFocusTool(null)}
      onFocus={() => onFocusTool(block.id)}
      onBlur={() => onFocusTool(null)}
    >
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="flex w-full items-center gap-2.5 px-3 py-2.5 text-left"
      >
        <span
          className={`grid size-6 shrink-0 place-items-center rounded-md ${
            block.status === "error" ? "bg-bad-soft" : block.status === "ok" ? "bg-ok-soft" : "bg-brand-soft"
          }`}
        >
          {statusIcon}
        </span>
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-2">
            <span className="font-mono text-[13px] font-semibold text-ink">{block.name}</span>
            <span className="sr-only">{block.status === "running" ? "running" : block.status === "ok" ? "succeeded" : "failed"}</span>
            <span className="truncate font-mono text-[11.5px] text-muted">{summarizeInput(block.input)}</span>
          </span>
          <span className={`mt-0.5 block truncate text-[12.5px] ${block.status === "error" ? "text-bad" : "text-ink-2"}`}>{summary}</span>
        </span>
        {block.durationMs !== undefined && (
          <span className="shrink-0 rounded-md border border-line bg-surface px-1.5 py-0.5 font-mono text-[11px] text-muted">
            {formatMs(block.durationMs)}
          </span>
        )}
        <Chevron className={`size-4 shrink-0 text-faint transition-transform ${open ? "rotate-90" : ""}`} />
      </button>
      {open && (
        <div className="space-y-2.5 border-t border-line px-3 py-3">
          <JsonBlock label="Input" value={block.input} />
          {block.output && (
            <div>
              <div className="mb-1 flex items-center justify-between">
                <span className="text-[11px] font-semibold tracking-wide text-muted uppercase">Result</span>
                <button type="button" onClick={() => setRaw((r) => !r)} className="text-[12px] font-medium text-brand hover:underline">
                  {raw ? "Hide raw output" : "Show raw output"}
                </button>
              </div>
              <p className={`text-[13px] ${block.status === "error" ? "text-bad" : "text-ink-2"}`}>
                <Wrench className="mr-1 inline size-3.5 align-[-2px] text-faint" />
                {summary}
              </p>
              {raw && <JsonBlock value={block.output} />}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function JsonBlock({ label, value }: { label?: string; value: unknown }) {
  return (
    <div>
      {label && <div className="mb-1 text-[11px] font-semibold tracking-wide text-muted uppercase">{label}</div>}
      <pre className="max-h-72 overflow-auto rounded-lg border border-line bg-surface p-2.5 font-mono text-[11.5px] leading-relaxed text-ink-2">
        {JSON.stringify(value, null, 2)}
      </pre>
    </div>
  );
}

function DoneFooter({ run }: { run: Run }) {
  const d = run.done!;
  const tokens = d.usage.input_tokens + d.usage.output_tokens;
  const ok = d.status === "succeeded";
  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line px-4 py-2 text-[11.5px] text-muted">
      <span className={`inline-flex items-center gap-1 font-medium ${ok ? "text-ok" : "text-bad"}`}>
        {ok ? <Check className="size-3" /> : <Cross className="size-3" />}
        {d.status.replace("_", " ")}
      </span>
      <span>{formatMs(d.duration_ms)}</span>
      <span>
        {d.iterations} tool turn{d.iterations === 1 ? "" : "s"}
      </span>
      <span>
        {tokens.toLocaleString("en-US")} tokens{run.mode === "replay" ? " (est.)" : ""}
      </span>
      <span className="ml-auto font-mono">run #{d.id}</span>
    </div>
  );
}
