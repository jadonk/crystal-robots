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
const profile = await mkdtemp(join(tmpdir(), "crd-challenge-"));
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
    const { data } = await page("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
    await writeFile(join(screenshotDir, name), Buffer.from(data, "base64"));
  }
  const base = `http://127.0.0.1:${server.address().port}`;
  await viewport(1280);
  await page("Page.navigate", { url: `${base}/tournament/?seed=1&names=counter,rabbit,rook,target` });
  await waitFor('document.querySelector("#bracket .bracket-match") !== null', 180);
  if (!await evaluate('document.querySelector("#champion").textContent.trim().length > 3')) throw new Error("Champion missing");
  const recorded = await evaluate('document.querySelector("#pools details:first-child .fight-link:last-child").textContent.split(" · ").at(-1)');
  await evaluate('document.querySelector("#pools details:first-child").open = true; document.querySelector("#pools details:first-child .fight-link:last-child").click()');
  await waitFor('document.querySelector("#replay svg") !== null', 90);
  if (!await evaluate('document.querySelector("#replay-result").textContent.includes("recorded winner")')) throw new Error("Replay winner missing");
  const shown = await evaluate('document.querySelector("#replay-result").textContent.match(/Winner: (.*?) ·/)[1]');
  if (shown !== recorded) throw new Error(`Winner mismatch: ${shown} vs ${recorded}`);
  for (const theme of ["light", "dark"]) for (const width of [1280, 360]) {
    await viewport(width, width === 360 ? 780 : 900, theme);
    if (await evaluate('document.documentElement.scrollWidth > document.documentElement.clientWidth')) throw new Error(`Tournament overflow at ${width}/${theme}`);
    if (theme === "dark" && !await evaluate('getComputedStyle(document.querySelector("#replay svg > rect")).fill === "rgb(22, 40, 59)" && getComputedStyle(document.querySelector("#replay svg > rect")).stroke === "rgb(109, 131, 157)" && getComputedStyle(document.querySelector("#replay svg g[id^=robot-] text")).fill === "rgb(237, 244, 255)"')) throw new Error("Dark arena override missing");
    await screenshot(`tournament-${width}-${theme}.png`);
  }
  await viewport(1280);
  await page("Page.navigate", { url: `${base}/challenge/` });
  await waitFor('document.getElementById("check-level") && !document.getElementById("check-level").disabled', 90);
  await evaluate('document.getElementById("editor-source").value = `main("Your robot") do\n  drive(0, 50)\n  while true\n    sleep\n  end\nend\n`; document.getElementById("editor-source").dispatchEvent(new Event("input", {bubbles:true})); document.getElementById("check-level").click()');
  await waitFor('document.getElementById("challenge-status").textContent === "Level passed!"', 90);
  if (!await evaluate('document.querySelector("#challenge-replay svg") !== null')) throw new Error("Challenge replay missing");
  for (const theme of ["light", "dark"]) for (const width of [1280, 360]) {
    await viewport(width, width === 360 ? 780 : 900, theme);
    if (await evaluate('document.documentElement.scrollWidth > document.documentElement.clientWidth')) throw new Error(`Challenge overflow at ${width}/${theme}`);
    await screenshot(`challenge-${width}-${theme}.png`);
  }
  await viewport(1280);
  await page("Page.navigate", { url: `${base}/manual/` });
  await waitFor('document.querySelector("#api-groups .api-group") !== null', 90);
  for (const theme of ["light", "dark"]) for (const width of [1280, 360]) {
    await viewport(width, width === 360 ? 780 : 900, theme);
    if (await evaluate('document.documentElement.scrollWidth > document.documentElement.clientWidth')) throw new Error(`Manual overflow at ${width}/${theme}`);
    await evaluate('document.documentElement.style.scrollBehavior = "auto"; window.scrollTo(0, 0)');
    await screenshot(`manual-top-${width}-${theme}.png`);
    await evaluate('document.querySelector("#battlefield").scrollIntoView({behavior:"instant",block:"start"})');
    await screenshot(`manual-battlefield-${width}-${theme}.png`);
    await evaluate('document.querySelectorAll("#battlefield .manual-diagram")[1].scrollIntoView({behavior:"instant",block:"start"})');
    await screenshot(`manual-scanner-${width}-${theme}.png`);
  }
  await viewport(1280);
  await page("Page.navigate", { url: `${base}/workbench/` });
  await waitFor('document.querySelector("#run") && !document.querySelector("#run").disabled', 90);
  await evaluate('document.querySelector("#source").value = `main("Scout") do\n  drive(0, 50)\n  while true\n    puts loc_x\n    sleep\n  end\nend`; document.querySelector("#run").click()');
  await waitFor('document.querySelector("#robot-replay svg") !== null', 90);
  if (!await evaluate('document.querySelector("#robot-result").textContent.includes("Printed:")')) throw new Error("Workbench output missing");
  await evaluate('document.querySelector("#robot-replay .battle-playback-controls button").click(); const scrubber = document.querySelector("#robot-replay .battle-scrubber"); scrubber.value = scrubber.max; scrubber.dispatchEvent(new Event("input", {bubbles:true}))');
  const consoleEdge = await evaluate(`(() => {
    const box = document.querySelector("#robot-replay .battle-output");
    const top = box.getBoundingClientRect().top + parseFloat(getComputedStyle(box).paddingTop);
    const first = [...box.children].find((line) => line.getBoundingClientRect().bottom > top);
    return { top, lineTop: first?.getBoundingClientRect().top, scrollTop: box.scrollTop, text: first?.textContent };
  })()`);
  if (consoleEdge.lineTop < consoleEdge.top - 1) throw new Error(`Printed line clips at top: ${JSON.stringify(consoleEdge)}`);
  if (!await evaluate(`(() => {
    const svg = document.querySelector("#robot-replay svg").getBoundingClientRect();
    return [...document.querySelectorAll("#robot-replay svg g[id^=robot-] > text:not(.battle-print-label)")].every((label) => {
      const box = label.getBoundingClientRect();
      return box.left >= svg.left - 1 && box.right <= svg.right + 1;
    });
  })()`)) throw new Error("A robot name clipped outside the replay");
  for (const theme of ["light", "dark"]) for (const width of [1280, 360]) {
    await viewport(width, width === 360 ? 780 : 900, theme);
    if (await evaluate('document.documentElement.scrollWidth > document.documentElement.clientWidth')) throw new Error(`Workbench overflow at ${width}/${theme}`);
    await evaluate('document.documentElement.style.scrollBehavior = "auto"; window.scrollTo(0, 0)');
    await screenshot(`workbench-${width}-${theme}.png`);
    await evaluate('document.querySelector("#robot-preview").scrollIntoView({behavior:"instant",block:"start"})');
    await screenshot(`workbench-preview-${width}-${theme}.png`);
    await evaluate('document.querySelector("#robot-replay .battle-output").scrollIntoView({behavior:"instant",block:"start"})');
    await screenshot(`workbench-console-${width}-${theme}.png`);
  }
  if (errors.length) throw new Error(`Browser errors: ${errors.join(" | ")}`);
  console.log(JSON.stringify({ ok: true, recorded, shown, overflow360: false, browserErrors: 0, screenshots: screenshotDir ? 32 : 0 }));
} finally {
  ws?.close(); chrome.kill(); server.close();
  if (chrome.exitCode === null) await new Promise((resolve) => chrome.once("exit", resolve));
  // Chrome's helper processes can keep writing to the profile briefly after
  // the main process exits; a leftover temp dir must not fail a passed check.
  try { await rm(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 250 }); }
  catch (error) { console.error(`note: could not remove ${profile}: ${error.code || error}`); }
}
