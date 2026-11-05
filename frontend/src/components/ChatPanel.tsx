import { useEffect, useId, useRef, useState } from "react";
import type { SessionState } from "../lib/runReducer";
import type { Replay } from "../lib/types";
import { Graph, KeyIcon, Send, Stop, Wrench } from "./icons";
import { RunView } from "./RunView";

interface Props {
  session: SessionState;
  busy: boolean;
  replays: Replay[] | null;
  replaysError: string | null;
  hasKey: boolean;
  focusedTool: string | null;
  onFocusTool: (id: string | null) => void;
  onReplay: (r: Replay) => void;
  onAsk: (prompt: string) => void;
  onStop: () => void;
  onClear: () => void;
  onOpenSettings: () => void;
}

// What each recording exercises, shown on the starter cards.
const HINTS: Record<string, string> = {
  "db-server-outage": "impact_analysis",
  "email-gateway-outage": "impact_analysis",
  "overdue-laptops": "search_assets",
  "checkin-ap-00014": "checkin_asset",
  "dc1-warranty-maintenance": "search_assets → schedule_maintenance",
  "fleet-summary": "summarize_fleet",
  "checkout-macbook": "search_assets → checkout_asset",
  "checkout-conflict-ap-00016": "checkout_asset fails → search_assets",
};
const ORDER = Object.keys(HINTS);
const rank = (slug: string) => (ORDER.includes(slug) ? ORDER.indexOf(slug) : ORDER.length);
const sortReplays = (r: Replay[]) => [...r].sort((a, b) => rank(a.slug) - rank(b.slug));

export function ChatPanel(p: Props) {
  const scroller = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  const { runs } = p.session;
  const last = runs[runs.length - 1];
  const sorted = p.replays ? sortReplays(p.replays) : null;

  // Follow the stream while the reader is at the bottom; stop following when they scroll up.
  useEffect(() => {
    const el = scroller.current;
    if (el && stick.current) el.scrollTop = el.scrollHeight;
  }, [last?.blocks, runs.length]);

  return (
    <section aria-label="Chat" className="flex min-h-0 flex-col bg-canvas">
      <div
        ref={scroller}
        onScroll={(e) => {
          const el = e.currentTarget;
          stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 48;
        }}
        className="min-h-0 flex-1 overflow-y-auto"
      >
        <div className="mx-auto max-w-[760px] space-y-6 px-4 py-6 sm:px-6">
          {runs.length === 0 ? (
            <Welcome replays={sorted} error={p.replaysError} busy={p.busy} onReplay={p.onReplay} />
          ) : (
            <>
              {runs.map((run) => (
                <RunView key={run.key} run={run} focusedTool={p.focusedTool} onFocusTool={p.onFocusTool} />
              ))}
              {!p.busy && (
                <div className="flex justify-center">
                  <button type="button" onClick={p.onClear} className="text-[12.5px] font-medium text-muted hover:text-ink">
                    Clear conversation
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      <div className="border-t border-line bg-surface">
        <div className="mx-auto max-w-[760px] px-4 pt-3 pb-4 sm:px-6">
          {runs.length > 0 && sorted && (
            <div className="-mx-1 mb-2.5 flex gap-1.5 overflow-x-auto px-1 pb-1" role="list" aria-label="Recorded prompts">
              {sorted.map((r) => (
                <button
                  key={r.slug}
                  type="button"
                  role="listitem"
                  disabled={p.busy}
                  onClick={() => p.onReplay(r)}
                  className="shrink-0 rounded-full border border-line bg-surface px-3 py-1 text-[12.5px] whitespace-nowrap text-ink-2 hover:border-brand/40 hover:bg-brand-soft hover:text-brand-ink disabled:opacity-50"
                >
                  {r.prompt}
                </button>
              ))}
            </div>
          )}
          <Composer hasKey={p.hasKey} busy={p.busy} onAsk={p.onAsk} onStop={p.onStop} onOpenSettings={p.onOpenSettings} />
        </div>
      </div>
    </section>
  );
}

function Welcome({ replays, error, busy, onReplay }: { replays: Replay[] | null; error: string | null; busy: boolean; onReplay: (r: Replay) => void }) {
  return (
    <div className="pt-2 sm:pt-6">
      <h1 className="text-[26px] font-semibold tracking-tight text-balance">Ask your IT inventory.</h1>
      <p className="mt-2 max-w-[58ch] text-[15px] leading-relaxed text-muted">
        The agent answers with tools over 506 seeded assets, 12 services and their dependencies: impact analysis, search,
        check-in and check-out, maintenance. Watch each tool call stream in, and the blast radius draw itself in the graph.
      </p>

      <div className="mt-7 mb-3 flex items-center gap-2 text-[12px] font-semibold tracking-wide text-muted uppercase">
        Recorded prompts <span className="font-normal tracking-normal normal-case">· no key needed</span>
      </div>
      {error && (
        <p role="alert" className="rounded-lg border border-bad/25 bg-bad-soft px-3 py-2 text-sm text-bad">
          Couldn't load the recorded prompts: {error}
        </p>
      )}
      <div className="grid gap-2.5 sm:grid-cols-2">
        {(replays ?? Array.from({ length: 8 }, () => null)).map((r, i) =>
          r ? (
            <button
              key={r.slug}
              type="button"
              disabled={busy}
              onClick={() => onReplay(r)}
              className="group rounded-xl border border-line bg-surface p-3.5 text-left shadow-[0_1px_2px_rgb(14_23_38/0.04)] transition hover:-translate-y-px hover:border-brand/40 hover:shadow-md disabled:opacity-50"
            >
              <span className="block text-[14px] leading-snug font-medium text-ink group-hover:text-brand-ink">{r.prompt}</span>
              <span className="mt-2 flex items-center gap-1.5 font-mono text-[11px] text-muted">
                {HINTS[r.slug]?.startsWith("impact") ? <Graph className="size-3.5" /> : <Wrench className="size-3.5" />}
                {HINTS[r.slug] ?? "replay"}
              </span>
            </button>
          ) : (
            <div key={i} className="h-[78px] animate-pulse rounded-xl border border-line bg-surface" />
          ),
        )}
      </div>
    </div>
  );
}

function Composer({
  hasKey,
  busy,
  onAsk,
  onStop,
  onOpenSettings,
}: {
  hasKey: boolean;
  busy: boolean;
  onAsk: (prompt: string) => void;
  onStop: () => void;
  onOpenSettings: () => void;
}) {
  const [text, setText] = useState("");
  const id = useId();
  const submit = () => {
    const prompt = text.trim();
    if (!prompt || busy || !hasKey) return;
    onAsk(prompt);
    setText("");
  };

  return (
    <div>
      <div
        className={`flex items-end gap-2 rounded-xl border bg-surface p-1.5 pl-3 transition ${
          hasKey ? "border-line-strong focus-within:border-brand focus-within:ring-2 focus-within:ring-brand/15" : "border-line bg-canvas"
        }`}
      >
        <label htmlFor={id} className="sr-only">
          Ask anything about the inventory
        </label>
        <textarea
          id={id}
          rows={1}
          value={text}
          disabled={!hasKey}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              submit();
            }
          }}
          placeholder={hasKey ? "Ask anything about the inventory…" : "Add your key to ask anything"}
          className="max-h-40 min-h-[36px] flex-1 resize-none bg-transparent py-1.5 text-[14.5px] outline-none placeholder:text-faint disabled:cursor-not-allowed"
        />
        {busy ? (
          <button type="button" onClick={onStop} className="grid size-9 place-items-center rounded-lg bg-ink text-white hover:bg-ink-2" aria-label="Stop">
            <Stop className="size-3.5" />
          </button>
        ) : hasKey ? (
          <button
            type="button"
            onClick={submit}
            disabled={!text.trim()}
            className="grid size-9 place-items-center rounded-lg bg-brand text-white hover:bg-brand-ink disabled:opacity-40"
            aria-label="Send"
          >
            <Send />
          </button>
        ) : (
          <button
            type="button"
            onClick={onOpenSettings}
            className="inline-flex h-9 items-center gap-1.5 rounded-lg bg-brand px-3 text-[13px] font-medium text-white hover:bg-brand-ink"
          >
            <KeyIcon className="size-3.5" /> Add key
          </button>
        )}
      </div>
      <p className="mt-2 text-[12px] text-muted">
        {hasKey
          ? "Live run with your key: Enter to send, Shift+Enter for a new line. Recorded prompts still replay without it."
          : "No key set, so the recorded prompts are available: they replay real tool calls through the same streaming pipeline. Add your key to ask your own questions."}
      </p>
    </div>
  );
}
