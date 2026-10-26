import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
import { decodeWasm } from "../../site/wasm-view.js";

const bytes = await readFile(process.argv[2]);
const decoded = decodeWasm(bytes);
assert.equal(decoded.header.magic, "\0asm");
assert.equal(decoded.header.version, 1);
assert.deepEqual(decoded.sections.map((section) => section.id), [1, 2, 3, 6, 7, 10]);
const bodies = decoded.sections.find((section) => section.id === 10).bodies;
assert.ok(bodies.length > 0);
assert.ok(bodies.some((body) => body.instructions.some((op) => op.mnemonic === "i32.const")));
assert.ok(bodies.every((body) => body.instructions.every((op) => op.mnemonic !== "unknown")));
assert.ok(bodies.every((body) => body.instructions.every((op) => op.hex.length > 0 && op.end > op.start)));
console.log(JSON.stringify({ ok: true, sections: decoded.sections.map((section) => section.id), bodies: bodies.length }));
