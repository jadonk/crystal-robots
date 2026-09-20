// Headless check for site/editor's line-number gutter (Phase 6 follow-up):
// drives a real headless Chromium over the DevTools protocol (CDP) with
// only Node's built-in `http`/`fetch`/`WebSocket` -- no npm dependency to
// vendor -- and checks that (1) the textarea never soft-wraps a logical
// line onto a second visual row and (2) the gutter's scrollTop tracks the
// textarea's after a scroll. Exits 0 and prints `{"ok":true}` on success,
// exits 1 and prints the failing checks otherwise.
//
//   node spec/support/editor_gutter_check.mjs [chromium-binary]
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { spawn } from "node:child_process";

const chromiumBin = process.argv[2] || "chromium";
const repoRoot = new URL("../../", import.meta.url).pathname;
const siteRoot = join(repoRoot, "site");

const MIME = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".wasm": "application/wasm" };

const server = createServer(async (req, res) => {
  try {
    const path = normalize(join(siteRoot, decodeURIComponent(req.url.split("?")[0])));
    if (!path.startsWith(siteRoot)) throw new Error("outside site root");
    const body = await readFile(path);
    res.writeHead(200, { "Content-Type": MIME[extname(path)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404);
    res.end();
  }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

const userDataDir = await stat("/tmp").then(() => `/tmp/editor-gutter-check-${process.pid}`);
const chrome = spawn(
  chromiumBin,
  [
    "--headless=new",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    `--user-data-dir=${userDataDir}`,
    "--window-size=400,700",
    "--remote-debugging-port=0",
    "about:blank",
  ],
  { stdio: ["ignore", "ignore", "pipe"] },
);

let cdpPort;
const portReady = new Promise((resolve, reject) => {
  let buf = "";
  chrome.stderr.on("data", (chunk) => {
    buf += chunk.toString();
    const m = buf.match(/ws:\/\/127\.0\.0\.1:(\d+)\//);
    if (m) resolve(Number(m[1]));
  });
  chrome.on("exit", (code) => reject(new Error(`chromium exited early (${code})`)));
  setTimeout(() => reject(new Error("timed out waiting for chromium devtools port")), 10000);
});

async function cleanup() {
  chrome.kill();
  server.close();
}

try {
  cdpPort = await portReady;

  const versionInfo = await fetch(`http://127.0.0.1:${cdpPort}/json/version`).then((r) => r.json());
  const browserWs = new WebSocket(versionInfo.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    browserWs.addEventListener("open", resolve, { once: true });
    browserWs.addEventListener("error", reject, { once: true });
  });

  let nextId = 1;
  const pending = new Map();
  browserWs.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      if (msg.error) reject(new Error(msg.error.message));
      else resolve(msg.result);
    }
  });
  function send(method, params = {}) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      browserWs.send(JSON.stringify({ id, method, params }));
    });
  }

  const { targetId } = await send("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
  function sendOn(method, params = {}) {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      browserWs.send(JSON.stringify({ id, method, params, sessionId }));
    });
  }

  await sendOn("Page.enable");
  await sendOn("Page.navigate", { url: `http://127.0.0.1:${port}/editor/index.html` });
  await new Promise((resolve) => setTimeout(resolve, 1500)); // let the module script settle

  async function evaluate(expression) {
    const result = await sendOn("Runtime.evaluate", {
      expression,
      returnByValue: true,
      awaitPromise: true,
    });
    if (result.exceptionDetails) {
      throw new Error(result.exceptionDetails.exception?.description || JSON.stringify(result.exceptionDetails));
    }
    return result.result.value;
  }

  // A long comment line (must never wrap) plus enough lines to force a
  // scrollbar in the 400x700 viewport -- the same shape as the ticket's
  // counter-example repro.
  const longLine = "# ".padEnd(220, "x wrapped-comment-line-should-not-soft-wrap ");
  const lines = [longLine, ...Array.from({ length: 60 }, (_, i) => `puts(${i})`)];
  const source = lines.join("\n");

  await evaluate(`(() => {
    const el = document.getElementById("editor-source");
    el.value = ${JSON.stringify(source)};
    el.dispatchEvent(new Event("input", { bubbles: true }));
  })()`);

  const checks = {};

  checks.noSoftWrap =
    (await evaluate(`getComputedStyle(document.getElementById("editor-source")).whiteSpace`)) === "pre";
  checks.wrapAttributeOff =
    (await evaluate(`document.getElementById("editor-source").getAttribute("wrap")`)) === "off";
  checks.horizontalOverflowPossible = await evaluate(`(() => {
    const el = document.getElementById("editor-source");
    return el.scrollWidth > el.clientWidth;
  })()`);
  checks.gutterMatchesLineCount = await evaluate(`(() => {
    const gutter = document.getElementById("gutter");
    return gutter.children.length === ${lines.length};
  })()`);

  await evaluate(`(() => {
    const el = document.getElementById("editor-source");
    el.scrollTop = el.scrollHeight;
    el.dispatchEvent(new Event("scroll", { bubbles: true }));
  })()`);
  await new Promise((resolve) => setTimeout(resolve, 50));

  checks.scrollSyncedAfterScroll = await evaluate(`(() => {
    const src = document.getElementById("editor-source");
    const gutter = document.getElementById("gutter");
    return src.scrollTop > 0 && gutter.scrollTop === src.scrollTop;
  })()`);

  checks.sameLineHeight = await evaluate(`(() => {
    const src = getComputedStyle(document.getElementById("editor-source"));
    const gut = getComputedStyle(document.getElementById("gutter"));
    return src.lineHeight === gut.lineHeight && src.paddingTop === gut.paddingTop;
  })()`);

  const failed = Object.entries(checks).filter(([, ok]) => !ok);
  if (failed.length > 0) {
    console.log(JSON.stringify({ ok: false, failed: failed.map(([name]) => name), checks }));
    process.exitCode = 1;
  } else {
    console.log(JSON.stringify({ ok: true, checks }));
  }
} finally {
  await cleanup();
}
