// Battle section glue: no framework, no CDN, no rendering of its own.
// Collects the robots/seed/limit/cps inputs, calls `battle()` from
// wasi-shim.js (`crd_battle_run`, `Battle::Field#run_stepwise` --
// `src/battle/step_robot.cr` -- see `src/browser.cr`) and inserts the SVG
// string it returns: the same SMIL-animated replay the served `/battle`
// page renders (`CrystalRobots::Battle.svg_animation`,
// `src/battle/svg_replay.cr`), generated in Crystal either way, so there
// is exactly one renderer for the same picture on both pages. Reuses the
// module `app.js` already loaded: one `crystal-robots.wasm` compile for
// the whole page.
import { battle } from "./wasi-shim.js";
import { moduleReady } from "./app.js";

const MAX_ROBOTS = 4;

const slotsEl = document.getElementById("battle-slots");
const seedEl = document.getElementById("battle-seed");
const limitEl = document.getElementById("battle-limit");
const cpsEl = document.getElementById("battle-cps");
const runButton = document.getElementById("battle-run");
const statusEl = document.getElementById("battle-status");
const replayEl = document.getElementById("battle-replay");
const standingsEl = document.getElementById("battle-standings");

let examples = [];
let slots = [];

function createSlot(index) {
  const wrap = document.createElement("div");
  wrap.className = "robot-slot";

  const label = document.createElement("label");
  label.textContent = `Robot ${index + 1}`;
  label.htmlFor = `battle-r${index}-pick`;
  wrap.appendChild(label);

  const select = document.createElement("select");
  select.id = `battle-r${index}-pick`;
  select.appendChild(new Option("(empty)", ""));
  examples.forEach((r) => select.appendChild(new Option(r.name, r.name)));
  select.appendChild(new Option("Paste your own…", "__custom__"));
  wrap.appendChild(select);

  const nameInput = document.createElement("input");
  nameInput.type = "text";
  nameInput.placeholder = "Robot name";
  nameInput.id = `battle-r${index}-name`;
  nameInput.style.display = "none";
  wrap.appendChild(nameInput);

  const textarea = document.createElement("textarea");
  textarea.id = `battle-r${index}-source`;
  textarea.spellcheck = false;
  textarea.style.display = "none";
  wrap.appendChild(textarea);

  select.addEventListener("change", () => {
    const custom = select.value === "__custom__";
    nameInput.style.display = custom ? "" : "none";
    textarea.style.display = custom ? "" : "none";
    if (custom && !nameInput.value) nameInput.value = `robot${index + 1}`;
  });

  slotsEl.appendChild(wrap);
  return { select, nameInput, textarea };
}

async function loadExamples() {
  try {
    const response = await fetch("./robots.json");
    if (response.ok) examples = await response.json();
  } catch {
    examples = [];
  }
  for (let i = 0; i < MAX_ROBOTS; i++) {
    slots.push(createSlot(i));
  }
  // Two sensible defaults so Run Battle works with no editing.
  if (examples[0]) slots[0].select.value = examples[0].name;
  if (examples[1]) slots[1].select.value = examples[1].name;
}

function slotRobot(slot) {
  if (slot.select.value === "") return null;
  if (slot.select.value === "__custom__") {
    const name = slot.nameInput.value.trim();
    const source = slot.textarea.value;
    if (!name || !source.trim()) return null;
    return { name, source };
  }
  const found = examples.find((r) => r.name === slot.select.value);
  return found ? { name: found.name, source: found.source } : null;
}

function collectRobots() {
  return slots.map(slotRobot).filter((r) => r !== null);
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

async function runBattle() {
  const robots = collectRobots();
  if (robots.length < 2 || robots.length > 4) {
    statusEl.textContent = "Pick 2 to 4 robots first.";
    return;
  }
  runButton.disabled = true;
  statusEl.textContent = "Running…";
  standingsEl.innerHTML = "";
  replayEl.innerHTML = "";

  try {
    const compiledModule = await moduleReady;
    const seed = Math.max(0, Math.trunc(Number(seedEl.value)) || 0);
    const limit = Math.max(1, Math.trunc(Number(limitEl.value)) || 60000);
    const cps = Math.max(1, Math.trunc(Number(cpsEl.value)) || 300);
    const result = await battle(compiledModule, robots, seed, limit, cps);
    if (result.trapped) {
      // A malformed request, not a robot's own bug -- see
      // `Browser.battle_run`'s module comment in `src/browser.cr`: a bad
      // robot source is reported per-robot below, never a trap.
      statusEl.textContent = "Battle request failed.";
      standingsEl.textContent = result.stderr || "(the module aborted with no message)";
      return;
    }
    if (result.error) {
      statusEl.textContent = result.error;
      return;
    }
    statusEl.textContent = `${result.cycles} cycles.`;
    replayEl.innerHTML = result.svg;
    renderStandings(result);
  } finally {
    runButton.disabled = false;
  }
}

runButton.addEventListener("click", () => {
  runBattle().catch((e) => {
    statusEl.textContent = `Error: ${e.message}`;
  });
});

loadExamples()
  .then(() => moduleReady)
  .then(() => {
    statusEl.textContent = "Ready.";
    runButton.disabled = false;
  })
  .catch((e) => {
    statusEl.textContent = `Error: ${e.message}`;
  });
