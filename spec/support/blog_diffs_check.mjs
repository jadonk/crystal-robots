// Check every blog diff view in a real headless Chromium using only Node's
// built-in modules and the DevTools protocol. Exits 0 with {"ok":true} when
// every view loads, keyboard controls work, and its content fits at 360px.
//
//   node spec/support/blog_diffs_check.mjs [chromium-binary]
import { createServer } from "node:http";
import { readFile, stat, writeFile, mkdir } from "node:fs/promises";
import { extname, join, normalize } from "node:path";
import { spawn } from "node:child_process";

const chromiumBin = process.argv[2] || "chromium";
const repoRoot = new URL("../../", import.meta.url).pathname;
const siteRoot = join(repoRoot, "site");

const MIME = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".json": "application/json", ".wasm": "application/wasm" };

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

const userDataDir = await stat("/tmp").then(() => `/tmp/blog-diffs-check-${process.pid}`);
const chrome = spawn(
  chromiumBin,
  [
    "--headless=new",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    `--user-data-dir=${userDataDir}`,
    "--window-size=360,800",
    "--remote-debugging-port=0",
    "about:blank",
  ],
  { stdio: ["ignore", "ignore", "pipe"] },
);

let cdpPort;
const portReady = new Promise((resolve, reject) => {
  let buf = "";
  const failure = (message) =>
    new Error(`${message} (binary: ${chromiumBin}; stderr, last 2000 characters:\n${buf.slice(-2000)})`);
  chrome.stderr.on("data", (chunk) => {
    buf += chunk.toString();
    const m = buf.match(/ws:\/\/127\.0\.0\.1:(\d+)\//);
    if (m) {
      clearTimeout(timer);
      resolve(Number(m[1]));
    }
  });
  chrome.on("exit", (code) => {
    clearTimeout(timer);
    reject(failure(`chromium exited early (${code})`));
  });
  const timer = setTimeout(() => reject(failure("timed out waiting for chromium devtools port")), 30000);
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
  await sendOn("Runtime.enable");
  const errors = [];
  browserWs.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    if (msg.method === "Runtime.exceptionThrown") errors.push(msg.params.exceptionDetails.text);
    if (msg.method === "Runtime.consoleAPICalled" && msg.params.type === "error") errors.push("console.error");
  });
  await sendOn("Page.navigate", { url: `http://127.0.0.1:${port}/blog/index.html` });
  await new Promise((resolve) => setTimeout(resolve, 700));

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

  await sendOn("Emulation.setDeviceMetricsOverride", { width: 360, height: 800, deviceScaleFactor: 1, mobile: false });
  await evaluate(`document.documentElement.style.scrollBehavior = "auto"`);
  const ids = await evaluate(`Array.from(document.querySelectorAll('.diff-view[data-diff]')).map(x => x.dataset.diff)`);
  const checks = {};
  checks.allViewsPresent = ids.length === 37;
  for (const id of ids) {
    await evaluate(`document.querySelector('[data-diff="${id}"]').scrollIntoView()`);
    await new Promise((resolve) => setTimeout(resolve, 180));
    const ok = await evaluate(`(() => { const v = document.querySelector('[data-diff="${id}"]'); return !!v.querySelector('.diff-summary') && !!v.querySelector('.diff-files-heading') && (v.querySelector('.diff-excerpt .diff-add') || v.dataset.diff === 'c-u-2') && !v.dataset.error })()`);
    checks[id] = ok;
  }
  checks.noPageOverflow = await evaluate(`document.documentElement.scrollWidth <= innerWidth`);
  checks.notesFit = await evaluate(`Array.from(document.querySelectorAll('.diff-excerpt')).every((box) => {
    const edge = box.getBoundingClientRect().right;
    return Array.from(box.querySelectorAll('.diff-note, .diff-callout')).every((note) => {
      const rect = note.getBoundingClientRect();
      return rect.left >= box.getBoundingClientRect().left - 1 && rect.right <= edge + 1 && note.scrollWidth <= note.clientWidth + 1;
    });
  })`);
  checks.codeFits = await evaluate(`Array.from(document.querySelectorAll('.diff-scroll')).every((box) => box.scrollWidth <= box.clientWidth + 1)`);
  const toggle = await evaluate(`(() => { const b = document.querySelector('.diff-toggle'); b.focus(); return !!b })()`);
  // CDP sends a real Enter key to the focused button.
  await sendOn("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
  await sendOn("Input.dispatchKeyEvent", { type: "char", text: "\r", unmodifiedText: "\r", key: "Enter", windowsVirtualKeyCode: 13 });
  await sendOn("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
  checks.keyboardToggle = toggle && await evaluate(`document.querySelector('.diff-toggle').getAttribute('aria-expanded') === 'true'`);
  checks.noConsoleErrors = errors.length === 0;
  if (process.env.BLOG_SCREENSHOTS) {
    const outputDir = process.env.BLOG_SCREENSHOTS;
    await mkdir(outputDir, { recursive: true });
    for (const theme of ["light", "dark"]) {
      await sendOn("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: theme }] });
      for (const width of [1280, 360]) {
        await sendOn("Emulation.setDeviceMetricsOverride", { width, height: 850, deviceScaleFactor: 1, mobile: false });
        for (const [name, selector] of [["primer", "#reading-crystal"], ["minimal-module", "#c-a-2 .diff-view"], ["checker", "#c-a-12 .diff-view"]]) {
          await evaluate(`document.querySelector(${JSON.stringify(selector)}).scrollIntoView({ behavior: 'instant', block: 'start' })`);
          await new Promise((resolve) => setTimeout(resolve, 250));
          const image = await sendOn("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
          await writeFile(`${outputDir}/${name}-${width}-${theme}.png`, Buffer.from(image.data, "base64"));
        }
      }
    }
  }
  const failed = Object.entries(checks).filter(([, ok]) => !ok).map(([name]) => name);
  console.log(JSON.stringify({ ok: !failed.length, failed, checks, errors }));
  if (failed.length) process.exitCode = 1;
} finally {
  await cleanup();
}
