// Thin page glue: no framework, no CDN. Everything that talks WASI lives
// in wasi-shim.js; this file just wires the textarea/button to it and
// renders the report `crd_run` returns (see `src/browser.cr`).
import { friendlyError } from "../friendly-errors.js";
import { run, check } from "../wasi-shim.js";
import { battle } from "../battle-client.js";
import { decodeFrames, mountBattlePlayback } from "../battle-playback.js";

const source = document.getElementById("source");
const runButton = document.getElementById("run");
const statusEl = document.getElementById("status");
const derivationEl = document.getElementById("derivation");
const problemsEl = document.getElementById("problems");
const interpreterEl = document.getElementById("interpreter");
const wasmEl = document.getElementById("wasm");
const robotResultEl = document.getElementById("robot-result");
const robotReplayEl = document.getElementById("robot-replay");
let previewPlayback;

async function loadModule() {
  statusEl.textContent = "Getting the browser ready…";
  const response = await fetch("../crystal-robots.wasm");
  if (!response.ok) {
    throw new Error(`fetch crystal-robots.wasm: ${response.status}`);
  }
  let compiledModule;
  try {
    compiledModule = await WebAssembly.compileStreaming(response.clone());
  } catch {
    // Falls back to a full buffer compile if the server does not send
    // `Content-Type: application/wasm` (compileStreaming requires it).
    compiledModule = await WebAssembly.compile(await response.arrayBuffer());
  }
  statusEl.textContent = "Ready.";
  return compiledModule;
}

// One compile of `crystal-robots.wasm` for the whole page: `battle.js`
// imports this same promise instead of fetching and compiling a second
// copy for the battle section.
export const moduleReady = loadModule();

function toHex(bytes) {
  return Array.from(bytes.slice(0, 64))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join(" ");
}

async function runSource() {
  runButton.disabled = true;
  statusEl.textContent = "Running…";
  derivationEl.textContent = "";
  problemsEl.textContent = "";
  interpreterEl.textContent = "";
  wasmEl.textContent = "";
  robotResultEl.textContent = "";
  if (previewPlayback) previewPlayback.stop();
  robotReplayEl.replaceChildren();
  const isRobot = /\bmain\s*\([^\n]*\)\s*do\b/.test(source.value);

  try {
    const compiledModule = await moduleReady;
    const report = isRobot ? await check(compiledModule, source.value) : await run(compiledModule, source.value);
    if (report.error || report.trapped) {
      // A syntax error, a runtime error or an unsupported-for-WASM
      // source (e.g. `puts "text"`) all land here: Crystal 1.18.2 has no
      // working `rescue` on this target, so any of those traps the whole
      // module instead of reporting gracefully (see `src/browser.cr`).
      // What it printed before trapping is still the useful part.
      statusEl.textContent = "Could not run this code.";
      derivationEl.textContent = friendlyError(report.error?.message || report.stderr || "(the program stopped without a message)");
      return;
    }

    statusEl.textContent = "Code checked.";
    derivationEl.textContent = report.derivation;

    problemsEl.textContent = report.problems.length === 0
      ? "Ready to run: names and the numbers passed to commands look right."
      : report.problems.map((problem) => friendlyError(problem.message || problem)).join("\n");

    if (report.problems.length === 0 && isRobot) {
      interpreterEl.textContent = "Robot programs run in a short fight against target; programs without a robot loop print here.";
      robotResultEl.textContent = "Starting a short fight against target…";
      const response = await fetch("../robots.json");
      if (!response.ok) throw new Error("Could not load the practice target.");
      const target = (await response.json()).find((robot) => robot.name === "target");
      if (!target) throw new Error("Could not find the practice target.");
      const result = await battle(compiledModule, [
        { name: "Your robot", source: source.value }, target,
      ], 1, 6000, 600, { maxFrames: 2000 });
      if (result.error || result.trapped) throw new Error(result.error || result.stderr || "Fight failed.");
      const yours = result.robots[0];
      const path = decodeFrames(result.frameBuffer).frames;
      const first = path[0]?.robots[0];
      const last = path.at(-1)?.robots[0];
      const traveled = first && last ? Math.round(Math.hypot(last.x - first.x, last.y - first.y)) : 0;
      const output = (yours.output || []).map((line) => line.text).join("\n");
      robotResultEl.textContent = `Your robot: ${yours.damage}% damage · ${result.cycles} turns\nPrinted: ${output || "(nothing yet)"}${yours.error ? `\n${friendlyError(yours.error)}` : ""}`;
      previewPlayback = mountBattlePlayback(robotReplayEl, result, 600);
    } else if (report.interpreter) {
      interpreterEl.textContent = `${report.interpreter.status}\n${report.interpreter.puts}`;
    }

    if (report.wasm_bytes) {
      wasmEl.textContent = `${report.wasm_len} bytes\n${toHex(report.wasm_bytes)}${report.wasm_bytes.length > 64 ? " …" : ""}`;
    } else if (isRobot) {
      wasmEl.textContent = "In a battle, your robot is compiled to WebAssembly whenever it can be.";
    }
  } finally {
    runButton.disabled = false;
  }
}

runButton.addEventListener("click", () => {
  runSource().catch((e) => {
    statusEl.textContent = `Problem: ${friendlyError(e.message)}`;
  });
});

moduleReady
  .then(runSource)
  .catch((e) => {
    statusEl.textContent = `Problem: ${friendlyError(e.message)}`;
  });
