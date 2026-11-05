import { useEffect, useId, useRef, useState } from "react";
import { isPlausibleKey, maskKey } from "../lib/keyStore";
import { Close, Eye, EyeOff, Lock, Trash } from "./icons";

interface Props {
  open: boolean;
  currentKey: string | null;
  onClose: () => void;
  onSave: (key: string | null) => void;
}

export function SettingsModal({ open, currentKey, onClose, onSave }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  const [value, setValue] = useState("");
  const [reveal, setReveal] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();
  const noteId = useId();

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      setValue("");
      setError(null);
      setReveal(false);
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    const key = value.trim();
    if (!isPlausibleKey(key)) {
      setError("That doesn't look like an API key (printable characters, no spaces).");
      return;
    }
    onSave(key);
    onClose();
  };

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => e.target === ref.current && onClose()}
      aria-labelledby={`${inputId}-title`}
      className="m-auto w-[min(520px,calc(100vw-2rem))] rounded-2xl border border-line bg-surface p-0 text-ink shadow-2xl"
    >
      <form onSubmit={submit} className="p-6">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 id={`${inputId}-title`} className="text-lg font-semibold tracking-tight">
              Bring your own key
            </h2>
            <p className="mt-1 text-sm text-muted">Ask anything about the inventory with a live Claude run.</p>
          </div>
          <button type="button" onClick={onClose} className="rounded-md p-1 text-muted hover:bg-canvas" aria-label="Close">
            <Close />
          </button>
        </div>

        {currentKey && (
          <div className="mt-5 flex items-center justify-between rounded-lg border border-ok/25 bg-ok-soft px-3 py-2 text-sm">
            <span>
              Using <span className="font-mono text-[13px]">{maskKey(currentKey)}</span>
            </span>
            <button
              type="button"
              onClick={() => {
                onSave(null);
                onClose();
              }}
              className="inline-flex items-center gap-1 text-[13px] font-medium text-bad hover:underline"
            >
              <Trash className="size-3.5" /> Remove key
            </button>
          </div>
        )}

        <label htmlFor={inputId} className="mt-5 block text-sm font-medium">
          Anthropic API key
        </label>
        <div className="mt-1.5 flex rounded-lg border border-line-strong focus-within:border-brand focus-within:ring-2 focus-within:ring-brand/20">
          <input
            id={inputId}
            type={reveal ? "text" : "password"}
            autoComplete="off"
            spellCheck={false}
            placeholder="sk-ant-…"
            value={value}
            onChange={(e) => {
              setValue(e.target.value);
              setError(null);
            }}
            aria-describedby={noteId}
            aria-invalid={error ? true : undefined}
            className="min-w-0 flex-1 rounded-l-lg bg-transparent px-3 py-2 font-mono text-sm outline-none"
          />
          <button
            type="button"
            onClick={() => setReveal((r) => !r)}
            className="px-3 text-muted hover:text-ink"
            aria-label={reveal ? "Hide key" : "Show key"}
          >
            {reveal ? <EyeOff /> : <Eye />}
          </button>
        </div>
        {error && <p className="mt-1.5 text-[13px] text-bad">{error}</p>}

        <div id={noteId} className="mt-5 rounded-lg bg-canvas p-3.5 text-[13px] leading-relaxed text-ink-2">
          <div className="mb-1.5 flex items-center gap-1.5 font-medium text-ink">
            <Lock className="size-3.5" /> Privacy
          </div>
          <ul className="list-disc space-y-1 pl-4">
            <li>
              Kept in this tab's <code className="font-mono text-[12px]">sessionStorage</code> only. It is cleared when you close the
              tab and never written to cookies or localStorage.
            </li>
            <li>
              Sent only to the AssetPilot API, in the <code className="font-mono text-[12px]">x-anthropic-key</code> header of your own
              run and stream requests. The server uses it for that request and never stores or logs it.
            </li>
            <li>Replay chips never send it. Live runs are billed to your Anthropic account.</li>
          </ul>
        </div>

        <div className="mt-6 flex justify-end gap-2">
          <button type="button" onClick={onClose} className="h-9 rounded-lg px-3.5 text-sm font-medium text-ink-2 hover:bg-canvas">
            Cancel
          </button>
          <button
            type="submit"
            disabled={!value.trim()}
            className="h-9 rounded-lg bg-brand px-4 text-sm font-medium text-white hover:bg-brand-ink disabled:opacity-50"
          >
            Save key
          </button>
        </div>
      </form>
    </dialog>
  );
}
