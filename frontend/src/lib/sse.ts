// A Server-Sent Events parser for fetch() streams.
//
// EventSource cannot send request headers, and BYOK runs need `x-anthropic-key` on the stream
// request, so the stream is read with fetch + ReadableStream and parsed here. The parser follows the
// WHATWG event-stream rules: lines end in CRLF, LF or CR (a CR split across chunks is handled);
// lines starting with ":" are comments; `data` lines accumulate with "\n"; a blank line dispatches;
// an event with no data is dropped; a partial event at end of stream is discarded.

import { AGENT_EVENT_TYPES, type AgentEvent, type AgentEventType } from "./types";

export interface SSEMessage {
  event: string;
  data: string;
  id?: string;
  retry?: number;
}

export interface SSEParser {
  /** Feed a decoded text chunk; returns the messages completed by it. */
  feed(chunk: string): SSEMessage[];
  /** Signals end of stream. A trailing event without its blank line is discarded, per spec. */
  end(): SSEMessage[];
}

export function createSSEParser(): SSEParser {
  let buffer = "";
  let pendingCR = false;
  let eventType = "";
  let data: string[] = [];
  let hasData = false;
  let lastId: string | undefined;
  let retry: number | undefined;

  const dispatch = (out: SSEMessage[]) => {
    if (hasData) {
      const msg: SSEMessage = { event: eventType || "message", data: data.join("\n") };
      if (lastId !== undefined) msg.id = lastId;
      if (retry !== undefined) msg.retry = retry;
      out.push(msg);
    }
    eventType = "";
    data = [];
    hasData = false;
    retry = undefined;
  };

  const processLine = (line: string, out: SSEMessage[]) => {
    if (line === "") return dispatch(out);
    if (line.startsWith(":")) return;

    const colon = line.indexOf(":");
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? "" : line.slice(colon + 1);
    if (value.startsWith(" ")) value = value.slice(1);

    switch (field) {
      case "event":
        eventType = value;
        break;
      case "data":
        data.push(value);
        hasData = true;
        break;
      case "id":
        if (!value.includes("\0")) lastId = value;
        break;
      case "retry":
        if (/^\d+$/.test(value)) retry = Number(value);
        break;
      default:
        break; // unknown fields are ignored
    }
  };

  return {
    feed(chunk) {
      const out: SSEMessage[] = [];
      let text = chunk;
      // A chunk that ended in CR may be the first half of CRLF.
      if (pendingCR && text.startsWith("\n")) text = text.slice(1);
      pendingCR = false;
      buffer += text;

      let start = 0;
      for (let i = 0; i < buffer.length; i++) {
        const ch = buffer[i];
        if (ch !== "\n" && ch !== "\r") continue;
        processLine(buffer.slice(start, i), out);
        if (ch === "\r") {
          if (i + 1 === buffer.length) pendingCR = true;
          else if (buffer[i + 1] === "\n") i++;
        }
        start = i + 1;
      }
      buffer = buffer.slice(start);
      return out;
    },
    end() {
      buffer = "";
      eventType = "";
      data = [];
      hasData = false;
      return [];
    },
  };
}

/** Turns an SSE message into a typed agent event; unknown event names and bad JSON return null. */
export function toAgentEvent(msg: SSEMessage): AgentEvent | null {
  if (!AGENT_EVENT_TYPES.includes(msg.event as AgentEventType)) return null;
  try {
    const payload = JSON.parse(msg.data) as Record<string, unknown>;
    if (payload === null || typeof payload !== "object") return null;
    return { ...payload, type: msg.event } as AgentEvent;
  } catch {
    return null;
  }
}

export class HttpError extends Error {
  readonly status: number;
  readonly code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** Reads an SSE response body to the end, calling onMessage for each complete message. */
export async function readSSE(response: Response, onMessage: (msg: SSEMessage) => void): Promise<void> {
  if (!response.body) throw new Error("The stream response has no body");
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  const parser = createSSEParser();
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      for (const msg of parser.feed(value)) onMessage(msg);
    }
    parser.end();
  } finally {
    reader.releaseLock();
  }
}
