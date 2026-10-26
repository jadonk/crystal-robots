// Runs the tournament through the real browser WASI shim for the wasm32 spec.
import { readFile } from "node:fs/promises";
import { tournament } from "../../site/wasi-shim.js";

const [, , modulePath, requestPath] = process.argv;
const compiledModule = await WebAssembly.compile(await readFile(modulePath));
const request = JSON.parse(await readFile(requestPath, "utf8"));
const report = await tournament(compiledModule, request.robots, request.seed, request.limit);
process.stdout.write(JSON.stringify(report));
