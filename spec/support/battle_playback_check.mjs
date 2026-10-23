// Decodes a native Browser.battle_run frame log with the module used by
// the battle and editor Fight pages. Exits 0 with {"ok":true} on success.
// site/package.json marks site/*.js as ES modules so Node of any version imports them as ESM.
//
//   node spec/support/battle_playback_check.mjs frame-log.bin
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { decodeFrames } from "../../site/battle-playback.js";

const bytes = await readFile(process.argv[2]);
const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
const { robotCount, frames } = decodeFrames(buffer);
assert.equal(robotCount, 2);
assert.ok(frames.length > 1, "battle must produce multiple frames");

let activeRobots = 0;
let presentMissiles = 0;
let robotBeyond100 = false;
let robotMoved = false;
const firstPositions = new Array(robotCount);

for (const frame of frames) {
  frame.robots.forEach((robot, index) => {
    if (!robot.active) return;
    activeRobots++;
    assert.ok(robot.x >= 0 && robot.x <= 1000, `robot ${index} x=${robot.x} at cycle ${frame.cycle}`);
    assert.ok(robot.y >= 0 && robot.y <= 1000, `robot ${index} y=${robot.y} at cycle ${frame.cycle}`);
    if (robot.x > 100 || robot.y > 100) robotBeyond100 = true;
    if (firstPositions[index]) {
      if (robot.x !== firstPositions[index].x || robot.y !== firstPositions[index].y) robotMoved = true;
    } else {
      firstPositions[index] = { x: robot.x, y: robot.y };
    }
  });
  frame.missiles.forEach((missile, index) => {
    if (!missile.present) return;
    presentMissiles++;
    assert.ok(missile.x >= 0 && missile.x <= 1000, `missile ${index} x=${missile.x} at cycle ${frame.cycle}`);
    assert.ok(missile.y >= 0 && missile.y <= 1000, `missile ${index} y=${missile.y} at cycle ${frame.cycle}`);
  });
}

assert.ok(activeRobots > 0, "battle must contain active robots");
assert.ok(presentMissiles > 0, "battle must contain present missiles");
assert.ok(robotBeyond100, "at least one robot coordinate must exceed 100 meters");
assert.ok(robotMoved, "at least one robot must move");
console.log(JSON.stringify({ ok: true, frames: frames.length, activeRobots, presentMissiles }));
