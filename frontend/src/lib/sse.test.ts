import { describe, expect, it } from "vitest";
import { createSSEParser, readSSE, toAgentEvent, type SSEMessage } from "./sse";

const feedAll = (chunks: string[]) => {
  const p = createSSEParser();
  const out: SSEMessage[] = [];
  for (const c of chunks) out.push(...p.feed(c));
  out.push(...p.end());
  return out;
};

describe("createSSEParser", () => {
  it("parses event and data fields and dispatches on a blank line", () => {
    expect(feedAll(['event: text\ndata: {"step":1,"delta":"Hi"}\n\n'])).toEqual([
      { event: "text", data: '{"step":1,"delta":"Hi"}' },
    ]);
  });

  it("defaults the event name to message", () => {
    expect(feedAll(["data: x\n\n"])).toEqual([{ event: "message", data: "x" }]);
  });

  it("joins multiple data lines with newlines", () => {
    expect(feedAll(["data: a\ndata: b\ndata:\n\n"])[0].data).toBe("a\nb\n");
  });

  it("handles events split at every possible byte boundary", () => {
    const stream = 'event: progress\ndata: {"step":0,"delta":"Checking"}\n\nevent: done\ndata: {"id":3}\n\n';
    for (let i = 1; i < stream.length; i++) {
      const out = feedAll([stream.slice(0, i), stream.slice(i)]);
      expect(out.map((m) => m.event)).toEqual(["progress", "done"]);
      expect(out[1].data).toBe('{"id":3}');
    }
  });

  it("handles one character per chunk", () => {
    const out = feedAll([..."event: a\ndata: 1\n\nevent: b\ndata: 2\n\n"]);
    expect(out).toEqual([
      { event: "a", data: "1" },
      { event: "b", data: "2" },
    ]);
  });

  it("accepts CRLF and bare CR line endings, including a CRLF split across chunks", () => {
    expect(feedAll(["event: a\r\ndata: 1\r\n\r\n"])).toEqual([{ event: "a", data: "1" }]);
    expect(feedAll(["event: a\rdata: 1\r\r"])).toEqual([{ event: "a", data: "1" }]);
    expect(feedAll(["event: a\r", "\ndata: 1\r", "\n\r", "\n"])).toEqual([{ event: "a", data: "1" }]);
  });

  it("ignores comments, unknown fields and events without data", () => {
    expect(feedAll([": keep-alive\n\nfoo: bar\nevent: lonely\n\nevent: x\ndata: y\n\n"])).toEqual([{ event: "x", data: "y" }]);
  });

  it("strips only one leading space from values and keeps colons in data", () => {
    expect(feedAll(["data:  two spaces: yes\n\n"])[0].data).toBe(" two spaces: yes");
    expect(feedAll(["data:no-space\n\n"])[0].data).toBe("no-space");
  });

  it("tracks id and retry", () => {
    expect(feedAll(["id: 7\nretry: 1500\ndata: z\n\n"])).toEqual([{ event: "message", data: "z", id: "7", retry: 1500 }]);
  });

  it("discards a trailing event that never got its blank line", () => {
    expect(feedAll(["data: complete\n\ndata: partial\n"])).toEqual([{ event: "message", data: "complete" }]);
  });

  it("resets the event name between events", () => {
    const out = feedAll(["event: a\ndata: 1\n\ndata: 2\n\n"]);
    expect(out[1].event).toBe("message");
  });
});

describe("toAgentEvent", () => {
  it("types known agent events", () => {
    expect(toAgentEvent({ event: "tool_call", data: '{"step":1,"id":"t1","name":"get_asset","input":{}}' })).toEqual({
      type: "tool_call",
      step: 1,
      id: "t1",
      name: "get_asset",
      input: {},
    });
  });

  it("drops unknown events and malformed JSON", () => {
    expect(toAgentEvent({ event: "message", data: "{}" })).toBeNull();
    expect(toAgentEvent({ event: "text", data: "{not json" })).toBeNull();
    expect(toAgentEvent({ event: "text", data: "null" })).toBeNull();
  });
});

describe("readSSE", () => {
  it("reads a fetch Response body chunk by chunk, across multi-byte characters", async () => {
    const text = 'event: text\ndata: {"step":1,"delta":"café → ok"}\n\nevent: done\ndata: {"id":1}\n\n';
    const bytes = new TextEncoder().encode(text);
    const body = new ReadableStream<Uint8Array>({
      start(c) {
        for (let i = 0; i < bytes.length; i += 5) c.enqueue(bytes.slice(i, i + 5));
        c.close();
      },
    });
    const got: SSEMessage[] = [];
    await readSSE(new Response(body), (m) => got.push(m));
    expect(got.map((m) => m.event)).toEqual(["text", "done"]);
    expect(JSON.parse(got[0].data).delta).toBe("café → ok");
  });
});
