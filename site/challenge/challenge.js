import { battle } from "../battle-client.js";
import { loadModule } from "../load-module.js";
import { createEditorSurface } from "../editor/shared.js";
import { loadSavedSource, saveSource, loadProgress, saveProgress } from "../robot-store.js";
import { mountBattlePlayback } from "../battle-playback.js";
import { friendlyError } from "../friendly-errors.js";
import { evaluateBattle, evaluateSeries, evaluateTournament } from "./checks.js";

const $ = (id) => document.getElementById(id);
const levels = [
  { title: "Move", goal: "Drive somewhere. Finish more than 100 m from where you started while target waits.", hint: "Try drive(0, 50), then keep the program running with while true and sleep." },
  { title: "Look", goal: "Scan for target and fire a missile. It is fine if this shot misses.", hint: "Sweep angles with scan(angle, 10). Print the range to see what your robot sees:\nrange = scan(angle, 10)\nputs range\nWhen range is positive, call cannon(angle, range)." },
  { title: "Hit", goal: "Make target take any damage.", hint: "A missile reaches up to 700 m. Sweep the scanner and fire again when the cannon reloads." },
  { title: "Win", goal: "Destroy target before time runs out.", hint: "Keep scanning and firing after the first hit. Move closer if target is out of range." },
  { title: "Moving target", goal: "Beat rabbit in at least 2 of 3 fights.", hint: "Rabbit moves but does not shoot. Scan often and keep tracking it." },
  { title: "Fight back", goal: "Beat counter in at least 2 of 3 fights.", hint: "Counter shoots back. Keep moving while you scan and fire." },
  { title: "The tournament", goal: "Reach the final rounds against bundled robots. Win the whole event for a badge of honor.", hint: "Use the tournament page to inspect each loss. Improve your code here, then try again." },
];
const starter = `main("Your robot") do\n  drive(0, 50)\n  while true\n    sleep\n  end\nend\n`;
let level = 1, robots = [], playback, moduleReady;
const source = $("editor-source");
const progress = loadProgress();
const surface = createEditorSurface({ sourceEl: source, gutterEl: $("gutter"), problemsEl: $("problems"), cheatEl: $("cheat-sheet"), moduleReady: (moduleReady = loadModule()) });
surface.loadCheatSheet();
source.value = loadSavedSource() || starter; surface.renderGutter();
source.addEventListener("input", () => { saveSource(source.value); });
function showLevel(n) {
  level = n; $("level-number").textContent = `LEVEL ${n} OF 7`; $("level-title").textContent = levels[n - 1].title;
  $("goal").textContent = levels[n - 1].goal; $("hint").textContent = levels[n - 1].hint;
  $("feedback").textContent = ""; $("enter-tournament").hidden = n !== 7;
  for (const button of $("levels").children) { button.setAttribute("aria-current", Number(button.dataset.level) === n ? "step" : "false"); button.textContent = `${button.dataset.level}. ${levels[Number(button.dataset.level) - 1].title}${progress[button.dataset.level] ? " ✓" : ""}`; }
}
levels.forEach((item, index) => { const button = document.createElement("button"); button.type = "button"; button.dataset.level = String(index + 1); button.addEventListener("click", () => showLevel(index + 1)); $("levels").append(button); });
showLevel(Math.min(7, Math.max(1, Number(progress.current) || 1)));
function showReplay(result, label) {
  if (playback) playback.stop(); $("challenge-replay").hidden = false;
  $("battle-result").textContent = `${label}`; playback = mountBattlePlayback($("replay"), result, 600);
}
async function run() {
  $("check-level").disabled = true; $("feedback").textContent = ""; $("challenge-status").textContent = "Checking your robot…";
  try {
    const checked = await surface.runCheck();
    if (checked.trapped || checked.error || checked.problems?.length) { $("challenge-status").textContent = "Fix the code problems above, then try again."; return; }
    const module = await moduleReady;
    const yours = { name: "Your robot", source: source.value };
    let outcome, deciding;
    if (level <= 4) {
      $("challenge-status").textContent = "Running a battle against target…";
      deciding = await battle(module, [yours, robots.find((r) => r.name === "target")], 1, 60000, 600, { maxFrames: 20000 });
      if (deciding.trapped || deciding.error) throw new Error(deciding.error || deciding.stderr);
      outcome = evaluateBattle(level, deciding);
    } else if (level <= 6) {
      const opponent = level === 5 ? "rabbit" : "counter"; let wins = 0, losses = 0;
      for (const seed of [1, 2, 3]) {
        $("challenge-status").textContent = `Running ${opponent}, fight ${seed} of 3…`;
        const result = await battle(module, [yours, robots.find((r) => r.name === opponent)], seed, 60000, 600, { maxFrames: 20000 });
        if (result.trapped || result.error) throw new Error(result.error || result.stderr);
        if (result.winner === "Your robot") wins++; else losses++;
        if (!deciding && (wins === 2 || losses === 2)) deciding = result;
        if (seed === 3 && !deciding) deciding = result;
      }
      outcome = evaluateSeries(wins, opponent);
    } else {
      $("challenge-status").textContent = "Running tournament pools and final rounds…";
      const entrants = [yours, ...["target", "rabbit", "counter"].map((name) => robots.find((r) => r.name === name))];
      const report = await new Promise((resolve, reject) => {
        const worker = new Worker("../tournament/worker.js", { type: "module" });
        worker.onmessage = ({ data }) => {
          if (data.progress) $("challenge-status").textContent = data.progress;
          if (data.report) { worker.terminate(); resolve(data.report); }
          if (data.error) { worker.terminate(); reject(new Error(data.error)); }
        };
        worker.onerror = (event) => { worker.terminate(); reject(new Error(event.message)); };
        worker.postMessage({ robots: entrants, seed: 1, limit: 60000, engine: new URLSearchParams(location.search).get("engine") === "interpreter" ? "interpreter" : "compiled" });
      });
      if (report.trapped || report.error) throw new Error(report.error || report.stderr);
      outcome = evaluateTournament(report);
      const fight = [...report.pools.flatMap((pool) => pool.fights), ...report.rounds.flatMap((round) => round.matches.flatMap((match) => match.games))].findLast((game) => game.entrants.includes("Your robot"));
      if (fight) deciding = await battle(module, fight.entrants.map((name) => entrants.find((r) => r.name === name)), fight.seed, report.limit, 600, { maxFrames: 20000 });
    }
    if (deciding) showReplay(deciding, `Winner: ${deciding.winner || "draw"}`);
    $("feedback").className = outcome.pass ? "ok" : "bad"; $("feedback").textContent = outcome.reason;
    $("challenge-status").textContent = outcome.pass ? "Level passed!" : "Try again.";
    if (outcome.pass) { progress[level] = true; progress.current = Math.min(7, level + 1); saveProgress(progress); for (const button of $("levels").children) if (Number(button.dataset.level) === level && !button.textContent.endsWith(" ✓")) button.textContent += " ✓"; }
  } catch (error) { $("challenge-status").textContent = `Problem: ${friendlyError(error.message)}`; }
  finally { $("check-level").disabled = false; }
}
$("check-level").addEventListener("click", run);
async function init() { const response = await fetch("../robots.json"); if (!response.ok) throw new Error("Could not load robots.json"); robots = await response.json(); await moduleReady; $("challenge-status").textContent = "Ready."; $("check-level").disabled = false; }
init().catch((error) => { $("challenge-status").textContent = `Problem: ${friendlyError(error.message)}`; });
