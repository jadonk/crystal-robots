import { run, ast, battle } from "./wasi-shim.js";
import { mountBattlePlayback } from "./battle-playback.js";
import { renderWasm } from "./wasm-view.js";

const names = ["sniper", "rook", "rabbit", "counter"];
const colors = ["#4C97FF", "#FF8C1A", "#59C059", "#FFAB19"];
const $ = (id) => document.getElementById(id);
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const tabs = [...document.querySelectorAll("[role=tab]")];
let examples = [], compiledModule, report, playback, selected = 0, layer = "source";
let artifacts = new Map(), derivationRows = [], pass = 0, passTimer = null;
let seed = seedFromURL();

function seedFromURL() {
  const raw = new URLSearchParams(location.search).get("seed");
  if (raw !== null && /^\d+$/.test(raw)) return Number(raw) >>> 0;
  return crypto.getRandomValues(new Uint32Array(1))[0];
}
function status(message) { $("battle-status").textContent = message; }
function errorMessage(error) { return error?.message || String(error); }

async function loadModule() {
  const response = await fetch("./crystal-robots.wasm");
  if (!response.ok) throw new Error(`Could not load WebAssembly (${response.status})`);
  try { return await WebAssembly.compileStreaming(response.clone()); }
  catch { return WebAssembly.compile(await response.arrayBuffer()); }
}

function renderLegend(damages = null) {
  const legend = $("battle-legend");
  legend.replaceChildren();
  examples.forEach((robot, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "legend-robot";
    button.setAttribute("aria-pressed", String(index === selected));
    const swatch = document.createElement("span");
    swatch.className = "robot-swatch";
    swatch.style.backgroundColor = colors[index];
    const label = document.createElement("strong");
    label.textContent = robot.name;
    const damage = document.createElement("span");
    damage.className = "legend-damage";
    damage.textContent = `${damages?.[index] ?? 0}% damage`;
    button.append(swatch, label, damage);
    button.addEventListener("click", () => { selected = index; renderLegend(damages); renderSelected(); });
    legend.append(button);
  });
}
function updateDamage(frame) {
  const values = frame.robots.map((robot) => robot.damage);
  $("battle-legend").querySelectorAll(".legend-damage").forEach((el, i) => {
    el.textContent = `${values[i]}% damage`;
  });
}
function showFinalStandings() {
  if (!report) return;
  $("battle-legend").querySelectorAll(".legend-damage").forEach((el, i) => {
    const robot = report.robots[i];
    el.textContent = `${robot.damage}% · ${report.winner === robot.name ? "winner" : robot.active ? "survived" : "destroyed"}`;
  });
}

async function rematch(nextSeed) {
  $("rematch").disabled = true;
  if (playback) playback.stop();
  $("battle-replay").replaceChildren();
  $("battle-loading").hidden = false;
  $("seed-readout").textContent = `Seed ${nextSeed}`;
  status("Running the match…");
  const result = await battle(compiledModule, examples, nextSeed, 60000, 450, { maxFrames: 5000 });
  if (result.trapped || result.error) throw new Error(result.stderr || result.error || "Battle failed");
  report = result;
  renderLegend();
  playback = mountBattlePlayback($("battle-replay"), result, 450, {
    autoplay: !reducedMotion.matches,
    onFrame: updateDamage,
    onEnd: showFinalStandings,
  });
  $("battle-loading").hidden = true;
  $("rematch").disabled = false;
  status(`${result.cycles.toLocaleString()} cycles recorded · select a robot to inspect its layers`);
  renderEngine();
}

function showLayer(next) {
  layer = next;
  tabs.forEach((tab) => { tab.setAttribute("aria-selected", String(tab.dataset.layer === next)); tab.tabIndex = tab.dataset.layer === next ? 0 : -1; });
  document.querySelectorAll(".layer-panel").forEach((panel) => { panel.hidden = panel.id !== `panel-${next}`; });
  if (next === "derivation") renderDerivation();
  if (next === "engine") renderEngine();
  if (next === "wasm" || next === "ast" || next === "derivation") loadArtifact(selected);
}
function renderSelected() {
  const robot = examples[selected];
  if (!robot) return;
  $("selected-robot").textContent = `/ ${robot.name}`;
  $("source-code").textContent = robot.source;
  $("open-editor").href = `./editor/?robot=${encodeURIComponent(robot.name)}`;
  derivationRows = [];
  pass = 0;
  $("derivation-view").textContent = "Loading passes…";
  $("ast-view").textContent = "Loading tree…";
  $("wasm-view").textContent = "Loading bytes…";
  renderEngine();
  if (layer !== "source" && layer !== "engine") loadArtifact(selected);
}
function renderEngine() {
  const robot = report?.robots[selected];
  const view = $("engine-view");
  view.replaceChildren();
  if (!robot) { view.textContent = "Running battle…"; return; }
  for (const [label, value] of [["Cycles used", robot.cycles], ["Damage", `${robot.damage}%`], ["Restarts", robot.restarts], ["Error", robot.error || "None"]]) {
    const dt = document.createElement("dt"), dd = document.createElement("dd");
    dt.textContent = label; dd.textContent = String(value); view.append(dt, dd);
  }
}
function renderDerivation() {
  const view = $("derivation-view");
  if (!derivationRows.length) return;
  view.textContent = derivationRows.slice(0, pass + 1).join("\n");
  $("derivation-count").textContent = `Pass ${pass} / ${derivationRows.length - 1}`;
  view.scrollTop = view.scrollHeight;
}
function stopPasses() {
  if (passTimer) clearInterval(passTimer);
  passTimer = null;
  $("derivation-play").textContent = "Play passes";
}
function stepPass() {
  if (!derivationRows.length) return;
  pass = Math.min(pass + 1, derivationRows.length - 1);
  renderDerivation();
  if (pass === derivationRows.length - 1) stopPasses();
}
function buildTree(node) {
  const details = document.createElement("details");
  details.open = node.type === "Program" || node.type === "Statement";
  const summary = document.createElement("summary");
  summary.textContent = `${node.type} · ${node.text} · ${node.line}:${node.col}`;
  details.append(summary);
  if (node.children.length) {
    const children = document.createElement("ul");
    node.children.forEach((child) => { const li = document.createElement("li"); li.append(buildTree(child)); children.append(li); });
    details.append(children);
  }
  return details;
}
async function loadArtifact(index) {
  const robot = examples[index];
  if (!robot) return;
  if (!artifacts.has(robot.name)) {
    artifacts.set(robot.name, Promise.all([
      run(compiledModule, robot.source, { skipInterpret: true }),
      ast(compiledModule, robot.source),
    ]));
  }
  try {
    const [compiler, tree] = await artifacts.get(robot.name);
    if (index !== selected) return;
    if (compiler.trapped) throw new Error(compiler.stderr || "Compiler failed");
    if (tree.trapped || tree.error) throw new Error(tree.stderr || tree.error?.message || "Tree failed");
    derivationRows = compiler.derivation.trimEnd().split("\n");
    pass = Math.min(pass, derivationRows.length - 1);
    renderDerivation();
    $("ast-view").replaceChildren(buildTree(tree.root));
    if (compiler.wasm_bytes) renderWasm($("wasm-view"), compiler.wasm_bytes);
  } catch (error) {
    for (const id of ["derivation-view", "ast-view", "wasm-view"]) $(id).textContent = errorMessage(error);
  }
}

tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => showLayer(tab.dataset.layer));
  tab.addEventListener("keydown", (event) => {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
    event.preventDefault();
    const next = tabs[(index + (event.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length];
    next.focus(); showLayer(next.dataset.layer);
  });
});
$("derivation-step").addEventListener("click", () => { stopPasses(); stepPass(); });
$("derivation-play").addEventListener("click", () => {
  if (passTimer) { stopPasses(); return; }
  if (pass >= derivationRows.length - 1) pass = 0;
  $("derivation-play").textContent = "Pause passes";
  passTimer = setInterval(stepPass, 130);
});
$("rematch").addEventListener("click", async () => {
  seed = crypto.getRandomValues(new Uint32Array(1))[0];
  const url = new URL(location.href); url.searchParams.set("seed", String(seed)); history.replaceState(null, "", url);
  try { await rematch(seed); } catch (error) { status(errorMessage(error)); $("rematch").disabled = false; }
});

(async () => {
  const [module, response] = await Promise.all([loadModule(), fetch("./robots.json")]);
  if (!response.ok) throw new Error(`Could not load examples (${response.status})`);
  const all = await response.json();
  examples = names.map((name) => all.find((robot) => robot.name === name));
  if (examples.some((robot) => !robot)) throw new Error("A featured example is missing");
  compiledModule = module;
  renderLegend(); renderSelected();
  await rematch(seed);
})().catch((error) => { $("battle-loading").textContent = errorMessage(error); status(errorMessage(error)); });
