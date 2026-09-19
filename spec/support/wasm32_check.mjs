// CI driver for spec/wasm32_spec.cr: runs `site/crystal-robots.wasm`
// through the same `site/wasi-shim.js` the real page loads (no duplicate
// WASI implementation to drift out of sync) and prints the JSON report as
// one line, so a Crystal spec that cannot load a WASM module directly can
// still exercise the browser build end to end.
//
//   node spec/support/wasm32_check.mjs site/crystal-robots.wasm <source-file>
import { readFile } from "node:fs/promises";
import { run } from "../../site/wasi-shim.js";

const [, , modulePath, sourcePath] = process.argv;
const bytes = await readFile(modulePath);
const compiledModule = await WebAssembly.compile(bytes);
const source = await readFile(sourcePath, "utf8");

const report = await run(compiledModule, source);
if (report.wasm_bytes) {
  report.wasm_b64 = Buffer.from(report.wasm_bytes).toString("base64");
  delete report.wasm_bytes;
}
process.stdout.write(JSON.stringify(report));
