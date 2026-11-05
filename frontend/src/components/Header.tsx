import { KeyIcon, Logo } from "./icons";

export function ModeBadge({ live }: { live: boolean }) {
  return live ? (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border border-ok/25 bg-ok-soft px-2.5 py-1 text-xs font-medium text-ok">
      <span className="size-1.5 rounded-full bg-ok" aria-hidden />
      Live · your key
    </span>
  ) : (
    <span className="inline-flex items-center gap-1.5 whitespace-nowrap rounded-full border border-warn/25 bg-warn-soft px-2.5 py-1 text-xs font-medium text-warn">
      <span className="size-1.5 rounded-full bg-warn" aria-hidden />
      Replay<span className="hidden sm:inline"> · synthetic recording</span>
      <span className="sm:hidden"> · synthetic</span>
    </span>
  );
}

export function Header({ live, onSettings }: { live: boolean; onSettings: () => void }) {
  return (
    <header className="flex h-14 shrink-0 items-center gap-3 border-b border-line bg-surface px-4 sm:px-5">
      <div className="flex items-center gap-2.5">
        <Logo className="size-7 text-brand" />
        <div className="leading-tight">
          <div className="text-[15px] font-semibold tracking-tight">AssetPilot</div>
          <div className="hidden text-[11.5px] text-muted sm:block">IT inventory agent</div>
        </div>
      </div>
      <div className="ml-auto flex items-center gap-2 sm:gap-3">
        <ModeBadge live={live} />
        <button
          type="button"
          onClick={onSettings}
          className="inline-flex h-8 items-center gap-1.5 rounded-lg border border-line px-2.5 text-[13px] font-medium text-ink-2 hover:bg-canvas"
        >
          <KeyIcon />
          <span className="hidden sm:inline">{live ? "API key" : "Use your key"}</span>
          <span className="sr-only sm:hidden">API key settings</span>
        </button>
      </div>
    </header>
  );
}
