// CI driver for spec/wasm32_spec.cr's battle case: runs `crd_battle_run`
// (`site/crystal-robots.wasm`, `CrystalRobots::Battle::Field#run_stepwise`)
// through the same `site/wasi-shim.js` the real page loads, and prints the
// JSON report as one line -- the same shape as `wasm32_check.mjs`, but for
// a whole match instead of one parse/check/interpret call.
//
//   node spec/support/wasm32_battle_check.mjs site/crystal-robots.wasm <request-file>
//
// <request-file> is JSON: {"robots":[{"name":..,"source":..}, 2 to 4 of
// these], "seed":N, "limit":N, "cps":N} -- the same request `battle_run`'s
// own JS caller (the page) builds.
import { readFile } from "node:fs/promises";
import { battle } from "../../site/wasi-shim.js";

const [, , modulePath, requestPath] = process.argv;
const bytes = await readFile(modulePath);
const compiledModule = await WebAssembly.compile(bytes);
const request = JSON.parse(await readFile(requestPath, "utf8"));

const report = await battle(compiledModule, request.robots, request.seed, request.limit, request.cps);
process.stdout.write(JSON.stringify(report));
