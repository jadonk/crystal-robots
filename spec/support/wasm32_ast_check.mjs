import { readFile } from "node:fs/promises";
import { ast } from "../../site/wasi-shim.js";
const module = await WebAssembly.compile(await readFile(process.argv[2]));
const source = await readFile(process.argv[3], "utf8");
process.stdout.write(JSON.stringify(await ast(module, source)));
