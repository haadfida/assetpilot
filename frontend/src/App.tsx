import { lazy, Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { ChatPanel } from "./components/ChatPanel";
import { Header } from "./components/Header";
import { SettingsModal } from "./components/SettingsModal";
import { useAgentSession } from "./hooks/useAgentSession";
import { fetchReplays } from "./lib/api";
import { collectTouches, findImpact } from "./lib/graph";
import { loadKey, saveKey } from "./lib/keyStore";
import type { Replay } from "./lib/types";

// react-flow and dagre load in their own chunk, after the chat is interactive.
const GraphPanel = lazy(() => import("./components/GraphPanel"));

export default function App() {
  const [apiKey, setApiKey] = useState<string | null>(() => loadKey());
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [replays, setReplays] = useState<Replay[] | null>(null);
  const [replaysError, setReplaysError] = useState<string | null>(null);
  const [focusedTool, setFocusedTool] = useState<string | null>(null);
  const { state, busy, run, stop, clear } = useAgentSession(apiKey);

  useEffect(() => {
    let current = true;
    fetchReplays()
      .then((r) => current && setReplays(r))
      .catch((e: Error) => current && setReplaysError(e.message));
    return () => {
      current = false;
    };
  }, []);

  const onSaveKey = useCallback((key: string | null) => {
    saveKey(key);
    setApiKey(key);
  }, []);

  // The graph follows the most recent run that touched the graph, else the latest run.
  const graphRun = useMemo(() => {
    const withGraph = [...state.runs].reverse().find((r) => findImpact(r) || collectTouches(r).length > 0);
    return withGraph ?? state.runs[state.runs.length - 1];
  }, [state.runs]);

  const dbServer = replays?.find((r) => r.slug === "db-server-outage");

  return (
    <div className="flex h-full flex-col">
      <Header live={!!apiKey} onSettings={() => setSettingsOpen(true)} />
      <main className="grid min-h-0 flex-1 grid-cols-1 overflow-y-auto lg:grid-cols-[minmax(440px,5fr)_7fr] lg:overflow-hidden">
        <ChatPanel
          session={state}
          busy={busy}
          replays={replays}
          replaysError={replaysError}
          hasKey={!!apiKey}
          focusedTool={focusedTool}
          onFocusTool={setFocusedTool}
          onReplay={(r) => run(r.prompt, { replay: r.slug })}
          onAsk={(prompt) => run(prompt)}
          onStop={stop}
          onClear={clear}
          onOpenSettings={() => setSettingsOpen(true)}
        />
        <Suspense fallback={<div className="min-h-[460px] border-l border-line bg-surface" />}>
          <GraphPanel
            run={graphRun}
            focusedTool={focusedTool}
            canTry={!!dbServer && !busy}
            onTryPrompt={() => dbServer && run(dbServer.prompt, { replay: dbServer.slug })}
          />
        </Suspense>
      </main>
      <SettingsModal open={settingsOpen} currentKey={apiKey} onClose={() => setSettingsOpen(false)} onSave={onSaveKey} />
    </div>
  );
}
