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
  if (!await evaluate('[...document.querySelectorAll(".legend-engine")].every((el) => el.textContent === "running as WebAssembly")')) throw new Error("Landing robots did not use WebAssembly");
  if (await evaluate('document.querySelector("#battle-replay .battle-output") !== null')) throw new Error("A silent battle showed a print box");
  if (!await evaluate('document.querySelector("#seed-readout").textContent.includes("1")')) throw new Error("Seed readout is missing");
  for (const [layer, content] of [["source", "source-code"], ["derivation", "derivation-view"], ["ast", "ast-view"], ["wasm", "wasm-view"], ["engine", "engine-view"]]) {
    await evaluate(`document.getElementById("tab-${layer}").click()`);
    await waitFor(`document.getElementById("${content}").textContent.trim().length > 30`);
    if (layer === "wasm" && !await evaluate('document.getElementById("wasm-view").textContent.includes("br_table") && document.getElementById("wasm-view").textContent.includes("step: function")')) throw new Error("Resumable module listing missing");
    if (layer === "engine" && !await evaluate('document.getElementById("engine-view").textContent.includes("WebAssembly")')) throw new Error("Engine layer missing WebAssembly marker");
    if (!await evaluate(`!document.getElementById("panel-${layer}").hidden`)) throw new Error(`${layer} panel hidden`);
  }
  await evaluate('document.getElementById("tab-wasm").click()');
  await screenshot("landing-wasm-1280-light.png");
  await evaluate('document.getElementById("tab-source").click()');
  await screenshot("landing-1280-light.png");
  await viewport(1280, 900, "dark"); await screenshot("landing-1280-dark.png");
  await evaluate('document.getElementById("tab-wasm").click()'); await screenshot("landing-wasm-1280-dark.png"); await evaluate('document.getElementById("tab-source").click()');
  await viewport(360, 780, "light");
  const overflow = await evaluate('document.documentElement.scrollWidth > document.documentElement.clientWidth');
  if (overflow) throw new Error(`Horizontal page overflow at 360px: ${await evaluate('document.documentElement.scrollWidth')}`);
  await screenshot("landing-360-light.png");
  await evaluate('document.getElementById("tab-wasm").click()'); await screenshot("landing-wasm-360-light.png"); await evaluate('document.getElementById("tab-source").click()');
  await viewport(360, 780, "dark"); await screenshot("landing-360-dark.png");
  await evaluate('document.getElementById("tab-wasm").click()'); await screenshot("landing-wasm-360-dark.png"); await evaluate('document.getElementById("tab-source").click()');
  await viewport(1280, 900, "light");
  for (const layer of ["derivation", "ast", "wasm"]) {
    await evaluate(`document.getElementById("tab-${layer}").click()`);
    await screenshot(`landing-layer-${layer}.png`);
  }
  const outputCheck = await evaluate(`(async () => {
    const [{ battle }, { mountBattlePlayback }] = await Promise.all([
      import("/wasi-shim.js"), import("/battle-playback.js")
    ]);
    const module = await WebAssembly.compileStreaming(fetch("/crystal-robots.wasm"));
    const printer = { name: "Printer", source: 'main("Printer") do\\n  while true\\n    puts "hello"\\n    sleep\\n  end\\nend\\n' };
    const idle = { name: "Idle", source: 'main("Idle") do\\n  while true\\n    sleep\\n  end\\nend\\n' };
    const result = await battle(module, [printer, idle], 1, 300, 300, { maxFrames: 200 });
    if (result.error || result.trapped) throw new Error(result.error || result.stderr);
    window.checkPlayback?.stop();
    window.checkPlayback = mountBattlePlayback(document.getElementById("battle-replay"), result, 300, { autoplay: false });
    const legend = document.querySelectorAll("#battle-legend .legend-robot");
    legend.forEach((item, i) => {
      item.style.display = i >= result.robots.length ? "none" : "";
      if (i < result.robots.length) {
        item.querySelector("strong").textContent = result.robots[i].name;
        item.querySelector(".legend-damage").textContent = result.robots[i].damage + "% damage";
      }
    });
    document.getElementById("battle-status").textContent = "Printer says hello during this battle";
    const scrubber = document.querySelector("#battle-replay .battle-scrubber");
    scrubber.value = scrubber.max;
    scrubber.dispatchEvent(new Event("input", { bubbles: true }));
    const visible = document.querySelectorAll("#battle-replay .battle-output-line").length;
    const label = document.querySelector("#robot-0 .battle-print-label")?.getAttribute("visibility");
    scrubber.value = "0";
    scrubber.dispatchEvent(new Event("input", { bubbles: true }));
    const hidden = document.querySelectorAll("#battle-replay .battle-output-line").length;
    scrubber.value = scrubber.max;
    scrubber.dispatchEvent(new Event("input", { bubbles: true }));
    return { visible, hidden, label, consoleVisible: !!document.querySelector("#battle-replay .battle-output") };
  })()`);
  if (!outputCheck.consoleVisible || outputCheck.visible < 2 || outputCheck.hidden !== 0 || outputCheck.label !== "visible") throw new Error(`Printed lines did not follow the scrubber: ${JSON.stringify(outputCheck)}`);
  await evaluate('document.getElementById("tab-source").click()');
  await viewport(1280, 900, "light"); await screenshot("replay-puts-1280-light.png");
  await viewport(1280, 900, "dark"); await screenshot("replay-puts-1280-dark.png");
  await viewport(360, 780, "light"); await screenshot("replay-puts-360-light.png");
  await viewport(360, 780, "dark"); await screenshot("replay-puts-360-dark.png");
  await page("Page.navigate", { url: `http://127.0.0.1:${server.address().port}/?seed=1&engine=interpreter` });
  await waitFor('[...document.querySelectorAll(".legend-engine")].length === 4 && [...document.querySelectorAll(".legend-engine")].every((el) => el.textContent === "running in the interpreter")');
  if (errors.length) throw new Error(`Browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, layers: 5, overflow360: false, browserErrors: 0, printedLines: outputCheck.visible, screenshots: screenshotDir ? 15 : 0 }));
} finally {
  ws?.close(); chrome.kill(); server.close();
  if (chrome.exitCode === null) await new Promise((resolve) => chrome.once("exit", resolve));
  await rm(profile, { recursive: true, force: true });
}
