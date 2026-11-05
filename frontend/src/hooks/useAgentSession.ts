import { useCallback, useEffect, useReducer, useRef } from "react";
import { createRun, streamRun } from "../lib/api";
import { initialSession, isBusy, sessionReducer } from "../lib/runReducer";
import { HttpError } from "../lib/sse";

// Replays default to 1x so the stream reads like a live run; ?speed=4 in the page URL speeds them up.
function replaySpeed(): number | undefined {
  const v = Number(new URLSearchParams(window.location.search).get("speed"));
  return Number.isFinite(v) && v > 0 ? v : undefined;
}

let seq = 0;

export function useAgentSession(apiKey: string | null) {
  const [state, dispatch] = useReducer(sessionReducer, initialSession);
  const controllers = useRef(new Map<string, AbortController>());

  useEffect(() => {
    const map = controllers.current;
    return () => map.forEach((c) => c.abort());
  }, []);

  const run = useCallback(
    async (prompt: string, opts: { replay?: string } = {}) => {
      const key = `run-${Date.now()}-${++seq}`;
      const replay = opts.replay;
      // Chips always replay their recording, even with a key set; free text runs live.
      const sendKey = replay ? null : apiKey;
      dispatch({ type: "start", key, prompt, mode: replay ? "replay" : "live", replaySlug: replay });

      const controller = new AbortController();
      controllers.current.set(key, controller);
      try {
        const summary = await createRun({ prompt, replay, mode: replay ? "replay" : undefined, apiKey: sendKey }, controller.signal);
        dispatch({ type: "created", key, run: summary });
        await streamRun(summary.stream_url, {
          apiKey: summary.mode === "live" ? sendKey : null,
          speed: summary.mode === "replay" ? replaySpeed() : undefined,
          signal: controller.signal,
          onEvent: (event) => dispatch({ type: "event", key, event }),
        });
        dispatch({ type: "stream_ended", key });
      } catch (err) {
        if (controller.signal.aborted) {
          dispatch({ type: "failed", key, code: "cancelled", message: "Stopped." });
        } else if (err instanceof HttpError) {
          dispatch({ type: "failed", key, code: err.code, message: err.message });
        } else {
          dispatch({ type: "failed", key, code: "network_error", message: "Could not reach the AssetPilot API." });
        }
      } finally {
        controllers.current.delete(key);
      }
    },
    [apiKey],
  );

  const stop = useCallback(() => controllers.current.forEach((c) => c.abort()), []);
  const clear = useCallback(() => {
    controllers.current.forEach((c) => c.abort());
    dispatch({ type: "clear" });
  }, []);

  return { state, busy: isBusy(state), run, stop, clear };
}
