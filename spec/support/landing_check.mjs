import { createServer } from "node:http";
import { readFile, mkdtemp, rm, mkdir, writeFile } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";

const chromiumBin = process.argv[2] || "chromium";
const screenshotDir = process.argv[3];
const siteRoot = resolve(new URL("../../site/", import.meta.url).pathname);
const mime = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".wasm": "application/wasm", ".css": "text/css" };
const server = createServer(async (req, res) => {
  try {
    let requested = decodeURIComponent(req.url.split("?")[0]);
    if (requested.endsWith("/")) requested += "index.html";
    const path = resolve(siteRoot, "." + requested);
    if (!path.startsWith(siteRoot + sep)) throw new Error("outside site");
    const body = await readFile(path);
    res.writeHead(200, { "Content-Type": mime[extname(path)] || "application/octet-stream" });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const profile = await mkdtemp(join(tmpdir(), "crd-landing-"));
const chrome = spawn(chromiumBin, ["--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage", `--user-data-dir=${profile}`, "--remote-debugging-port=0", "about:blank"], { stdio: ["ignore", "ignore", "pipe"] });
let stderr = "";
const portReady = new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`Chromium timeout: ${stderr.slice(-2000)}`)), 30000);
  chrome.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
    const match = stderr.match(/ws:\/\/127\.0\.0\.1:(\d+)\//);
    if (match) { clearTimeout(timer); resolve(Number(match[1])); }
  });
  chrome.on("exit", (code) => { clearTimeout(timer); reject(new Error(`Chromium exited ${code}: ${stderr.slice(-2000)}`)); });
});
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let ws;
try {
  const cdpPort = await portReady;
  const info = await fetch(`http://127.0.0.1:${cdpPort}/json/version`).then((r) => r.json());
  ws = new WebSocket(info.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.addEventListener("open", resolve, { once: true }); ws.addEventListener("error", reject, { once: true }); });
  let id = 1, sessionId;
  const pending = new Map();
  const errors = [];
  ws.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id); pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    }
    if (msg.sessionId === sessionId && msg.method === "Runtime.exceptionThrown") errors.push(msg.params.exceptionDetails.text);
    if (msg.sessionId === sessionId && msg.method === "Runtime.consoleAPICalled" && msg.params.type === "error") errors.push(msg.params.args.map((arg) => arg.value || arg.description).join(" "));
  });
  function send(method, params = {}, onSession = false) {
    const current = id++;
    return new Promise((resolve, reject) => { pending.set(current, { resolve, reject }); ws.send(JSON.stringify({ id: current, method, params, ...(onSession ? { sessionId } : {}) })); });
  }
  const { targetId } = await send("Target.createTarget", { url: "about:blank" });
  ({ sessionId } = await send("Target.attachToTarget", { targetId, flatten: true }));
  const page = (method, params) => send(method, params, true);
  await page("Runtime.enable"); await page("Page.enable");
  async function evaluate(expression) {
    const result = await page("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
    return result.result.value;
  }
  async function waitFor(expression, seconds = 75) {
    const deadline = Date.now() + seconds * 1000;
    while (Date.now() < deadline) { if (await evaluate(expression)) return; await sleep(250); }
    throw new Error(`Timed out: ${expression}; status=${await evaluate('document.getElementById("battle-status")?.textContent')}`);
  }
  async function viewport(width, height = 900, theme = "light") {
    await page("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    await page("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: theme }] });
    await sleep(200);
  }
  async function screenshot(name) {
    if (!screenshotDir) return;
    await mkdir(screenshotDir, { recursive: true });
    const { data } = await page("Page.captureScreenshot", { format: "png", captureBeyondViewport: true });
    await writeFile(join(screenshotDir, name), Buffer.from(data, "base64"));
  }
  await viewport(1280);
  await page("Page.navigate", { url: `http://127.0.0.1:${server.address().port}/?seed=1` });
  await waitFor('document.querySelector("#battle-replay svg") !== null');
  if (!await evaluate('document.querySelector("#seed-readout").textContent.includes("1")')) throw new Error("Seed readout is missing");
  for (const [layer, content] of [["source", "source-code"], ["derivation", "derivation-view"], ["ast", "ast-view"], ["wasm", "wasm-view"], ["engine", "engine-view"]]) {
    await evaluate(`document.getElementById("tab-${layer}").click()`);
    await waitFor(`document.getElementById("${content}").textContent.trim().length > 30`);
    if (!await evaluate(`!document.getElementById("panel-${layer}").hidden`)) throw new Error(`${layer} panel hidden`);
  }
  await evaluate('document.getElementById("tab-source").click()');
  await screenshot("landing-1280-light.png");
  await viewport(1280, 900, "dark"); await screenshot("landing-1280-dark.png");
  await viewport(360, 780, "light");
  const overflow = await evaluate('document.documentElement.scrollWidth > document.documentElement.clientWidth');
  if (overflow) throw new Error(`Horizontal page overflow at 360px: ${await evaluate('document.documentElement.scrollWidth')}`);
  await screenshot("landing-360-light.png");
  await viewport(360, 780, "dark"); await screenshot("landing-360-dark.png");
  await viewport(1280, 900, "light");
  for (const layer of ["derivation", "ast", "wasm"]) {
    await evaluate(`document.getElementById("tab-${layer}").click()`);
    await screenshot(`landing-layer-${layer}.png`);
  }
  if (errors.length) throw new Error(`Browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, layers: 5, overflow360: false, browserErrors: 0, screenshots: screenshotDir ? 7 : 0 }));
} finally {
  ws?.close(); chrome.kill(); server.close();
  if (chrome.exitCode === null) await new Promise((resolve) => chrome.once("exit", resolve));
  await rm(profile, { recursive: true, force: true });
}
