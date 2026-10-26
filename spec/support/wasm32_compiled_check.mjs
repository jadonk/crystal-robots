import { readFile } from "node:fs/promises";
import { performance } from "node:perf_hooks";
import { battle, prepareRobotModules, tournament } from "../../site/wasi-shim.js";

const module = await WebAssembly.compile(await readFile(process.argv[2]));
const catalog = JSON.parse(await readFile("site/robots.json", "utf8"));
const anchor = catalog.find((r) => r.name === "sniper");
const others = catalog.filter((r) => r !== anchor);
let battles = 0;
function assert(ok, label) { if (!ok) throw new Error(label); }
function comparable(report) {
  const copy = { ...report };
  delete copy.frameBuffer;
  delete copy.engines;
  if (copy.robots) copy.robots = copy.robots.map(({ engine, ...robot }) => robot);
  return JSON.stringify(copy);
}
async function compareBattle(robots, seed, limit = 3000) {
  const robotModules = await prepareRobotModules(module, robots);
  assert(robotModules.every(Boolean), `bundled robot could not compile: ${robots.map((r) => r.name)}`);
  const options = { maxFrames: 100, engine: "compiled", robotModules };
  const compiled = await battle(module, robots, seed, limit, 300, options);
  const interpreted = await battle(module, robots, seed, limit, 300, { maxFrames: 100 });
  assert(!compiled.trapped && !interpreted.trapped, `battle trapped: ${compiled.stderr || interpreted.stderr}`);
  assert(compiled.robots.every((r) => r.engine === "wasm"), "compiled engine marker missing");
  assert(comparable(compiled) === comparable(interpreted), `report mismatch: ${robots.map((r) => r.name)}, seed ${seed}`);
  assert(Buffer.compare(Buffer.from(compiled.frameBuffer), Buffer.from(interpreted.frameBuffer)) === 0,
    `frame mismatch: ${robots.map((r) => r.name)}, seed ${seed}`);
  battles++;
}
for (const robot of catalog) {
  for (const seed of [1, 2, 3]) {
    await compareBattle([robot, anchor], seed);
    await compareBattle([robot, anchor, others[0], others[1]], seed);
  }
}
const eight = catalog.slice(0, 8);
const eightModules = await prepareRobotModules(module, eight);
assert(eightModules.every(Boolean), "eight robot tournament source could not compile");
const compiledTournament = await tournament(module, eight, 7, 3000, { engine: "compiled", robotModules: eightModules });
const interpretedTournament = await tournament(module, eight, 7, 3000);
assert(!compiledTournament.trapped && !interpretedTournament.trapped, "tournament trapped");
assert(Object.values(compiledTournament.engines).every((engine) => engine === "wasm"), "tournament engine marker missing");
assert(comparable(compiledTournament) === comparable(interpretedTournament), "full tournament report mismatch");

const printer = { name: "printer", source: 'main("printer") do\n puts "hello"\n while true\n  sleep\n end\nend\n' };
const fallbackModules = await prepareRobotModules(module, [printer, anchor]);
assert(fallbackModules[0] === null && fallbackModules[1], "unsupported source did not fall back");
const fallback = await battle(module, [printer, anchor], 1, 300, 300,
  { engine: "compiled", robotModules: fallbackModules, maxFrames: 100 });
assert(fallback.robots[0].engine === "interpreter" && fallback.robots[1].engine === "wasm", "per robot fallback failed");
assert(fallback.robots[0].output.some((line) => line.text === "hello"), "fallback robot did not run");

// This also exercises reentry into Crystal from env imports while a long
// four robot fight and every match of an eight robot tournament are live.
const four = catalog.slice(0, 4);
const fourModules = await prepareRobotModules(module, four);
const timed = {};
for (const engine of ["compiled", "interpreter"]) {
  const start = performance.now();
  const report = await battle(module, four, 1, 60000, 300,
    { engine, robotModules: fourModules, maxFrames: 500 });
  assert(!report.trapped && report.cycles > 0, `${engine} stress fight failed`);
  timed[engine] = Math.round(performance.now() - start);
}
assert(timed.compiled <= timed.interpreter * 2,
  `compiled 60,000-cycle fight was more than 2x slower: ${JSON.stringify(timed)}`);
const stress = await tournament(module, eight, 11, 60000, { engine: "compiled", robotModules: eightModules });
assert(!stress.trapped && !stress.error && stress.fight_count > 0, "full eight robot stress tournament failed");
console.log(JSON.stringify({ ok: true, battles, tournamentFights: compiledTournament.fight_count,
  stressTournamentFights: stress.fight_count, milliseconds: timed }));
