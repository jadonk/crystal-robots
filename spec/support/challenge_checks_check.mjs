import { readFile } from "node:fs/promises";
import { battle } from "../../site/wasi-shim.js";
import { evaluateBattle } from "../../site/challenge/checks.js";

const module = await WebAssembly.compile(await readFile("site/crystal-robots.wasm"));
const catalog = JSON.parse(await readFile("site/robots.json", "utf8"));
const target = catalog.find((robot) => robot.name === "target");
const passSource = catalog.find((robot) => robot.name === "hunter").source;
const failSource = target.source;
for (const level of [1, 2, 3, 4]) {
  const passReport = await battle(module, [{ name: "Your robot", source: passSource }, target], 1, 60000, 600, { maxFrames: 20000 });
  const failReport = await battle(module, [{ name: "Your robot", source: failSource }, target], 1, 60000, 600, { maxFrames: 20000 });
  const passed = evaluateBattle(level, passReport);
  const failed = evaluateBattle(level, failReport);
  if (!passed.pass || failed.pass || !passed.reason || !failed.reason) throw new Error(`Level ${level}: expected a pass and a fail, got ${JSON.stringify({ passed, failed })}`);
}
console.log(JSON.stringify({ ok: true, levels: 4, passes: 4, fails: 4 }));
