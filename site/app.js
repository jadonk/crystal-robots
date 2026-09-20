// Thin page glue: no framework, no CDN. Everything that talks WASI lives
// in wasi-shim.js; this file just wires the textarea/button to it and
// renders the report `crd_run` returns (see `src/browser.cr`).
import { run } from "./wasi-shim.js";

const source = document.getElementById("source");
const runButton = document.getElementById("run");
const statusEl = document.getElementById("status");
const derivationEl = document.getElementById("derivation");
const problemsEl = document.getElementById("problems");
const interpreterEl = document.getElementById("interpreter");
const wasmEl = document.getElementById("wasm");

async function loadModule() {
  statusEl.textContent = "Loading crystal-robots.wasm…";
  const response = await fetch("./crystal-robots.wasm");
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

  try {
    const compiledModule = await moduleReady;
    const report = await run(compiledModule, source.value);
    if (report.trapped) {
      // A syntax error, a runtime error or an unsupported-for-WASM
      // source (e.g. `puts "text"`) all land here: Crystal 1.18.2 has no
      // working `rescue` on this target, so any of those traps the whole
      // module instead of reporting gracefully (see `src/browser.cr`).
      // What it printed before trapping is still the useful part.
      statusEl.textContent = "Could not compile this source.";
      derivationEl.textContent = report.stderr || "(the module aborted with no message)";
      return;
    }

    statusEl.textContent = `${report.passes} passes.`;
    derivationEl.textContent = report.derivation;

    problemsEl.textContent = report.problems.length === 0
      ? "Checks passed: every name is defined and every call has the right number of arguments."
      : report.problems.join("\n");

    if (report.interpreter) {
      interpreterEl.textContent = `${report.interpreter.status}\n${report.interpreter.puts}`;
    } else if (report.problems.length === 0) {
      interpreterEl.textContent = "Did not finish in the preview step budget (e.g. a fight loop); skipped.";
    }

    if (report.wasm_bytes) {
      wasmEl.textContent = `${report.wasm_len} bytes\n${toHex(report.wasm_bytes)}${report.wasm_bytes.length > 64 ? " …" : ""}`;
    }
  } finally {
    runButton.disabled = false;
  }
}

runButton.addEventListener("click", () => {
  runSource().catch((e) => {
    statusEl.textContent = `Error: ${e.message}`;
  });
});

moduleReady
  .then(runSource)
  .catch((e) => {
    statusEl.textContent = `Error: ${e.message}`;
  });
