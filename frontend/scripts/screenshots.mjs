// End-to-end check and README screenshots: replays recorded prompts in headless Chromium against a
// running app (Vite dev server proxying a Rails API), waits for each run to finish, asserts the tool
// cards and graph rendered, and fails on any console error or failed request.
//
//   bin/rails s -p 3100 & (cd frontend && npm run dev) &
//   npm run screenshots                      # APP_URL=http://localhost:5173 by default
//
// Uses playwright-core with an installed Chromium; set CHROMIUM_PATH to pick a binary.

import { chromium } from "playwright-core";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";

const APP_URL = process.env.APP_URL ?? "http://localhost:5173";
const OUT = fileURLToPath(new URL("../docs/screenshots/", import.meta.url));
const SPEED = process.env.REPLAY_SPEED ?? "4";
mkdirSync(OUT, { recursive: true });

const scenarios = [
  { file: "impact-db-server.png", prompt: "What breaks if DB-Server goes down?", expectTools: ["impact_analysis"], graph: true, openPeople: true },
  { file: "impact-email-gateway.png", prompt: "What happens if the Email Gateway goes down?", expectTools: ["impact_analysis"], graph: true },
  {
    file: "maintenance-dc1.png",
    prompt: "Schedule maintenance for assets with expired warranty in Data-Center-1",
    expectTools: ["search_assets", "schedule_maintenance"],
    graph: true,
    hoverTool: "schedule_maintenance",
  },
  {
    file: "checkout-conflict.png",
    prompt: "Check out AP-00016 to Marguerite Little",
    expectTools: ["checkout_asset", "search_assets"],
    graph: true,
    expandFirstTool: true,
  },
];

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
const problems = [];

function watch(page, label) {
  page.on("console", (m) => (m.type() === "error" || m.type() === "warning") && problems.push(`${label}: console ${m.type()}: ${m.text()}`));
  page.on("pageerror", (e) => problems.push(`${label}: page error: ${e.message}`));
  page.on("requestfailed", (r) => problems.push(`${label}: request failed: ${r.url()} ${r.failure()?.errorText}`));
  page.on("response", (r) => r.status() >= 400 && problems.push(`${label}: HTTP ${r.status()} ${r.url()}`));
}

const escape = (t) => t.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
// The starter card for a prompt (its accessible name is the prompt followed by the tools it uses).
const starter = (page, prompt) => page.getByRole("button", { name: new RegExp(`^${escape(prompt)}`) }).first();

async function open(label) {
  const page = await context.newPage();
  watch(page, label);
  await page.goto(`${APP_URL}/?speed=${SPEED}`, { waitUntil: "networkidle" });
  await starter(page, "What breaks if DB-Server goes down?").waitFor();
  return page;
}

// 1. Welcome screen
{
  const page = await open("welcome");
  await page.screenshot({ path: `${OUT}welcome.png` });
  console.log("✓ welcome.png");
  await page.close();
}

// 2. Replays
for (const s of scenarios) {
  const page = await open(s.file);
  const t0 = Date.now();
  await starter(page, s.prompt).click();
  await page.getByText(/run #\d+/).waitFor({ timeout: 60_000 });
  const ms = Date.now() - t0;

  for (const tool of s.expectTools) {
    const n = await page.locator("article").getByText(tool, { exact: true }).count();
    if (n === 0) problems.push(`${s.file}: no tool card for ${tool}`);
  }
  if ((await page.getByText("Synthetic recording.").count()) === 0) problems.push(`${s.file}: synthetic label missing`);
  if (s.graph) {
    await page.locator(".react-flow__node").first().waitFor({ timeout: 10_000 });
    await page.waitForTimeout(700); // fitView animation
  }
  const nodes = await page.locator(".react-flow__node").count();
  const edges = await page.locator(".react-flow__edge").count();
  if (s.expandFirstTool) await page.locator("article button[aria-expanded]").filter({ hasText: s.expectTools[0] }).first().click();
  await page.mouse.move(10, 10); // off the cards, so the graph is not in focus mode
  // Hovering a tool card highlights the nodes it touched.
  if (s.hoverTool) await page.locator("article button[aria-expanded]").filter({ hasText: s.hoverTool }).first().hover();
  if (s.openPeople) await page.getByRole("button", { name: /People to notify/ }).click();
  await page.waitForTimeout(250);
  await page.screenshot({ path: `${OUT}${s.file}` });
  console.log(`✓ ${s.file}: done in ${ms} ms, ${nodes} nodes, ${edges} edges`);
  await page.close();
}

// 3. Settings modal
{
  const page = await open("settings");
  await page.getByRole("button", { name: /use your key/i }).click();
  await page.getByLabel("Anthropic API key").waitFor();
  await page.screenshot({ path: `${OUT}settings.png` });
  console.log("✓ settings.png");
  await page.close();
}

// 4. BYOK: with a key in sessionStorage, free text is enabled and the key goes on BOTH the create and
// the stream request. The API is mocked here (no real key exists), so nothing reaches Anthropic.
{
  const page = await context.newPage();
  watch(page, "byok");
  const FAKE = "sk-ant-test-0000000000000000";
  await page.addInitScript((k) => sessionStorage.setItem("assetpilot.anthropicKey", k), FAKE);
  const seen = {};
  await page.route("**/api/agent/runs", async (route) => {
    seen.create = route.request().headers()["x-anthropic-key"];
    await route.fulfill({
      status: 201,
      contentType: "application/json",
      body: JSON.stringify({ data: { id: 999, prompt: "Which servers are out of warranty?", model: "claude-opus-5-5", mode: "live", status: "queued", recorded: null, replay_slug: null, stream_url: "/api/agent/runs/999/stream" } }),
    });
  });
  await page.route("**/api/agent/runs/999/stream*", async (route) => {
    seen.stream = route.request().headers()["x-anthropic-key"];
    const frames = [
      ["text", { step: 0, delta: "Mocked live answer." }],
      ["done", { id: 999, status: "succeeded", mode: "live", recorded: null, model: "claude-opus-5-5", iterations: 0, stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }, duration_ms: 5, steps: 1 }],
    ];
    await route.fulfill({ status: 200, contentType: "text/event-stream", body: frames.map(([e, d]) => `event: ${e}\ndata: ${JSON.stringify(d)}\n\n`).join("") });
  });
  await page.goto(APP_URL, { waitUntil: "networkidle" });
  if ((await page.getByText("Live · your key").count()) === 0) problems.push("byok: live badge missing");
  await page.getByLabel("Ask anything about the inventory").fill("Which servers are out of warranty?");
  await page.keyboard.press("Enter");
  await page.getByText(/run #999/).waitFor({ timeout: 10_000 });
  if (seen.create !== FAKE || seen.stream !== FAKE) problems.push(`byok: key not sent on both requests (${JSON.stringify(seen)})`);
  else console.log("✓ byok: key sent on create and stream, live badge shown");
  await page.close();
}

await browser.close();

if (problems.length) {
  console.error(`\n${problems.length} problem(s):\n${problems.join("\n")}`);
  process.exit(1);
}
console.log("\nNo console errors, failed requests or missing elements.");
