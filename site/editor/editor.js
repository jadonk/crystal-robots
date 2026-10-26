// site/editor: fork an example or a saved wiki robot into an editable
// buffer, check it live against the browser-hosted checker (`crd_check`,
// `Browser.check` in `src/browser.cr`, via `check()` in
// `../wasi-shim.js`) on a short debounce after typing stops, show one
// consolidated cheat-sheet beside the editor (`../cheat-sheet.json`,
// built from `src/web/robot_api.cr`'s `RobotAPI::GROUPS`/`ENTRIES` --
// the same data the served pages' panel renders, so it can never drift),
// and fight the buffer against opponents (`crd_battle_run`, via
// `battle()`, the same call `../workbench/battle.js` makes). No framework, no CDN,
// same CSP as the rest of `site/` (no inline script). Phase 6.
import { friendlyError } from "../friendly-errors.js";
import { battle } from "../battle-client.js";
import { createEditorSurface } from "./shared.js";
import { loadSavedSource, saveSource } from "../robot-store.js";
import { mountBattlePlayback } from "../battle-playback.js";

// Requests the larger of the two frame budgets `Browser.battle_run`
// accepts (`src/browser.cr`), same as `../workbench/battle.js`'s in-page battle
// (Phase 6): the fight preview here plays back live too
// (`mountBattlePlayback`), not a fire-and-forget SMIL animation, so a
// long fight is worth recording in full rather than downsampled to the
// served page's much smaller default.
const MAX_FRAMES = 20000;

const pickerEl = document.getElementById("picker");
const forkButton = document.getElementById("fork");
const statusEl = document.getElementById("status");
const sourceEl = document.getElementById("editor-source");
const gutterEl = document.getElementById("gutter");
const problemsEl = document.getElementById("problems");
const cheatEl = document.getElementById("cheat-sheet");

async function loadModule() {
  statusEl.textContent = "Getting the browser ready…";
  const response = await fetch("../crystal-robots.wasm");
  if (!response.ok) {
    throw new Error(`fetch crystal-robots.wasm: ${response.status}`);
  }
  try {
    return await WebAssembly.compileStreaming(response.clone());
  } catch {
    // Falls back to a full buffer compile if the server does not send
    // `Content-Type: application/wasm` (compileStreaming requires it).
    return await WebAssembly.compile(await response.arrayBuffer());
  }
}
const moduleReady = loadModule();

// [{name, source, group: "Examples" | "Saved (wiki)"}]
let robots = [];

// The saved-robots picker only lights up same-origin, with an explicit
// `?wiki=<base>` query parameter naming where this deployment's
// crystal-robots app lives (see the module comment on `EDITOR_URL` in
// `src/web/cgi.cr`): no base, no attempt at all. GitHub Pages has no
// Fossil behind it to ask, and a plain same-origin-credentialed `fetch`
// never carries a session cookie cross-origin anyway, so guessing a base
// here would only ever produce a failed request.
const wikiBase = new URLSearchParams(location.search).get("wiki");

async function loadRobots() {
  const examples = await fetch("../robots.json")
    .then((r) => (r.ok ? r.json() : []))
    .catch(() => []);
  examples.forEach((r) => robots.push({ ...r, group: "Examples" }));

  if (wikiBase) {
    const saved = await fetch(`${wikiBase.replace(/\/$/, "")}/wiki-robots.json`, { credentials: "same-origin" })
      .then((r) => (r.ok ? r.json() : []))
      .catch(() => []);
    saved.forEach((r) => robots.push({ ...r, group: "Saved (wiki)" }));
  }

  fillOptgroups(pickerEl);
  pickerEl.disabled = robots.length === 0;
  forkButton.disabled = robots.length === 0;
}

function fillOptgroups(select) {
  select.innerHTML = "";
  let currentGroup = null;
  let optgroup = null;
  robots.forEach((r) => {
    if (r.group !== currentGroup) {
      currentGroup = r.group;
      optgroup = document.createElement("optgroup");
      optgroup.label = currentGroup;
      select.appendChild(optgroup);
    }
    optgroup.appendChild(new Option(r.name, r.name));
  });
}

// Copy-and-change is the plan's default (docs/PLAN.md, Phase 6): forking
// replaces the buffer outright rather than merging, so a fork always
// starts from exactly the picked robot's source.
function forkSelected() {
  const found = robots.find((r) => r.name === pickerEl.value);
  if (!found) return;
  sourceEl.value = found.source;
  saveSource(sourceEl.value);
  runCheck();
}

forkButton.addEventListener("click", forkSelected);

const sharedEditor = createEditorSurface({ sourceEl, gutterEl, problemsEl, cheatEl, moduleReady });
const runCheck = sharedEditor.runCheck;
const renderGutter = sharedEditor.renderGutter;
sharedEditor.loadCheatSheet();

// --- Fight: the buffer above (slot "yours") against up to three
// opponents, via the same `crd_battle_run` call `../workbench/battle.js` makes. ---

const MAX_OPPONENTS = 3;
const slotsEl = document.getElementById("fight-slots");
const seedEl = document.getElementById("fight-seed");
const limitEl = document.getElementById("fight-limit");
const cpsEl = document.getElementById("fight-cps");
const fightButton = document.getElementById("fight-run");
const fightStatusEl = document.getElementById("fight-status");
const replayEl = document.getElementById("fight-replay");
const standingsEl = document.getElementById("fight-standings");

let opponentSlots = [];
let activePlayback = null;

function buildFightSlots() {
  slotsEl.innerHTML = "";
  const yours = document.createElement("div");
  yours.className = "robot-slot";
  yours.innerHTML = "<label>Slot 1</label>yours (the buffer above)";
  slotsEl.appendChild(yours);

  opponentSlots = [];
  for (let i = 0; i < MAX_OPPONENTS; i++) {
    const wrap = document.createElement("div");
    wrap.className = "robot-slot";
    const label = document.createElement("label");
    label.textContent = `Opponent ${i + 1}`;
    label.htmlFor = `fight-o${i}-pick`;
    wrap.appendChild(label);
    const select = document.createElement("select");
    select.id = `fight-o${i}-pick`;
    select.appendChild(new Option("(empty)", ""));
    fillOptgroups(select);
    select.value = "";
    wrap.appendChild(select);
    slotsEl.appendChild(wrap);
    opponentSlots.push(select);
  }
  // One sensible default so Fight works with no editing: a robot other
  // than the one just forked into the buffer, when there is one.
  const other = robots.find((r) => r.name !== pickerEl.value) || robots[0];
  if (other) opponentSlots[0].value = other.name;
}

function renderStandings(report) {
  standingsEl.innerHTML = "";
  report.robots.forEach((r) => {
    const li = document.createElement("li");
    if (!r.active) li.className = "dead";
    const isWinner = report.winner === r.name;
    li.textContent = r.active
      ? `${r.name}: ${r.damage}% damage${isWinner ? " — winner" : ""}`
      : `${r.name}: destroyed${r.error ? ` (${r.error})` : ""}`;

    standingsEl.appendChild(li);
  });
  if (!report.winner && report.robots.every((r) => !r.active)) {
    const li = document.createElement("li");
    li.textContent = "Mutual destruction.";
    standingsEl.appendChild(li);
  }
}

async function runFight() {
  const buffer = { name: "yours", source: sourceEl.value };
  const opponents = opponentSlots
    .map((s) => robots.find((r) => r.name === s.value))
    .filter((r) => r !== undefined)
    .map((r) => ({ name: r.name, source: r.source }));
  const contestants = [buffer, ...opponents];
  if (contestants.length < 2 || contestants.length > 4) {
    fightStatusEl.textContent = "Pick one to three opponents first.";
    return;
  }
  fightButton.disabled = true;
  fightStatusEl.textContent = "Running…";
  standingsEl.innerHTML = "";
  if (activePlayback) activePlayback.stop();
  replayEl.innerHTML = "";

  try {
    const compiledModule = await moduleReady;
    const seed = Math.max(0, Math.trunc(Number(seedEl.value)) || 0);
    const limit = Math.max(1, Math.trunc(Number(limitEl.value)) || 60000);
    const cps = Math.max(1, Math.trunc(Number(cpsEl.value)) || 300);
    const result = await battle(compiledModule, contestants, seed, limit, cps, { maxFrames: MAX_FRAMES });
    if (result.trapped) {
      fightStatusEl.textContent = "Fight request failed.";
      standingsEl.textContent = friendlyError(result.stderr || "(the fight stopped without a message)");
      return;
    }
    if (result.error) {
      fightStatusEl.textContent = result.error;
      return;
    }
    fightStatusEl.textContent = "Fight recorded. Watch or pause the replay.";
    activePlayback = mountBattlePlayback(replayEl, result, cps);
    renderStandings(result);
  } finally {
    fightButton.disabled = false;
  }
}

fightButton.addEventListener("click", () => {
  runFight().catch((e) => {
    fightStatusEl.textContent = `Problem: ${friendlyError(e.message)}`;
  });
});

// --- Wire it all up. ---

async function init() {
  await loadRobots();
  if (robots[0]) {
    const requested = new URLSearchParams(location.search).get("robot");
    pickerEl.value = robots.some((robot) => robot.name === requested) ? requested : robots[0].name;
    if (!requested && loadSavedSource()) {
      sourceEl.value = loadSavedSource();
      runCheck();
    } else forkSelected();
  } else {
    renderGutter();
  }
  buildFightSlots();

  await moduleReady;
  statusEl.textContent = "Ready.";
  fightStatusEl.textContent = "Ready.";
  fightButton.disabled = false;
}

init().catch((e) => {
  statusEl.textContent = `Problem: ${friendlyError(e.message)}`;
  fightStatusEl.textContent = `Problem: ${friendlyError(e.message)}`;
});
