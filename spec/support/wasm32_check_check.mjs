// CI driver for spec/wasm32_spec.cr's editor-check cases: runs `crd_check`
// (`site/crystal-robots.wasm`, `Browser.check` in `src/browser.cr` -- the
// non-raising parse/check path the editor's live-typing loop uses) through
// the same `site/wasi-shim.js` the real page loads, and prints the JSON
// report as one line -- the same shape as `wasm32_check.mjs`, but for the
// editor's lighter `check()` call instead of the full `run()`.
//
//   node spec/support/wasm32_check_check.mjs site/crystal-robots.wasm <source-file>
import { readFile } from "node:fs/promises";
import { check } from "../../site/wasi-shim.js";

const [, , modulePath, sourcePath] = process.argv;
const bytes = await readFile(modulePath);
const compiledModule = await WebAssembly.compile(bytes);
const source = await readFile(sourcePath, "utf8");

const report = await check(compiledModule, source);
process.stdout.write(JSON.stringify(report));
