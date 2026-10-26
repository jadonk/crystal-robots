import { battle } from "../battle-client.js";
import { loadModule } from "../load-module.js";
import { loadSavedSource } from "../robot-store.js";
import { friendlyError } from "../friendly-errors.js";
import { mountBattlePlayback } from "../battle-playback.js";

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const requestedNames = params.get("names")?.split(",").filter(Boolean);
const seed = Number(params.get("seed"));
if (Number.isSafeInteger(seed) && seed >= 0) $("seed").value = String(seed);
let catalog = [], chosen = [], report, playback, moduleReady, worker;
function entry(name) { return catalog.find((robot) => robot.name === name); }
function cell(tag, value) { const el = document.createElement(tag); el.textContent = value; return el; }
function renderPicker() {
  const picker = $("entrant-picker"); picker.replaceChildren();
  for (const robot of catalog) {
    const label = document.createElement("label"); label.className = "entrant";
    const input = document.createElement("input"); input.type = "checkbox"; input.value = robot.name; input.checked = chosen.includes(robot.name);
    input.addEventListener("change", () => { chosen = [...picker.querySelectorAll("input:checked")].map((e) => e.value); });
    label.append(input, cell("strong", robot.name), cell("small", robot.description || robot.origin)); picker.append(label);
  }
}
function fightButton(fight) {
  const button = cell("button", `${fight.entrants.join(" vs ")} · start ${fight.seed} · ${fight.winner || "draw"}`);
  button.type = "button"; button.className = "fight-link";
  button.addEventListener("click", () => replayFight(fight));
  return button;
}
function render(report) {
  $("results").hidden = false; $("pools").replaceChildren(); $("bracket").replaceChildren(); $("rejected").replaceChildren();
  if (report.rejected?.length) {
    const h = cell("h2", "Rejected robots"); $("rejected").append(h);
    for (const robot of report.rejected) $("rejected").append(cell("p", `${robot.name}: ${friendlyError(robot.error)}`));
  }
  if (report.error) { $("results").hidden = true; $("status").textContent = report.error; return; }
  report.pools.forEach((pool, index) => {
    const section = document.createElement("section"); section.append(cell("h3", `Pool ${index + 1}`));
    const fights = document.createElement("div"); fights.className = "fight-list";
    const pairings = new Map();
    for (const fight of pool.fights) {
      const key = [...fight.entrants].sort().join(" vs ");
      if (!pairings.has(key)) pairings.set(key, []);
      pairings.get(key).push(fight);
    }
    for (const [pair, games] of pairings) {
      const details = document.createElement("details");
      const last = games.at(-1);
      details.append(cell("summary", `${pair} · ${games.length} ${games.length === 1 ? "fight" : "fights"} · final: ${last.winner || "draw"}`));
      const replayLinks = document.createElement("div"); replayLinks.className = "match-games";
      games.forEach((game) => replayLinks.append(fightButton(game)));
      details.append(replayLinks); fights.append(details);
    }
    section.append(fights);
    const table = document.createElement("table"); table.append(cell("caption", "Standings"));
    const head = document.createElement("tr"); ["Rank", "Robot", "Points"].forEach((x) => head.append(cell("th", x))); table.append(head);
    pool.standings.forEach((standing) => { const row = document.createElement("tr"); [standing.rank, standing.name, standing.points].forEach((x) => row.append(cell("td", String(x)))); table.append(row); });
    section.append(table); $("pools").append(section);
  });
  report.rounds.forEach((round) => {
    const column = document.createElement("section"); column.className = "bracket-round"; column.append(cell("h3", round.label));
    round.matches.forEach((match) => {
      const box = document.createElement("div"); box.className = "bracket-match";
      match.entrants.forEach((name) => { const line = cell("div", name || "Bye"); if (name === match.winner) line.className = "winner"; box.append(line); });
      if (match.games.length) {
        const games = document.createElement("details"); games.className = "match-games";
        games.append(cell("summary", `${match.games.length} ${match.games.length === 1 ? "fight" : "fights"} · final: ${match.games.at(-1).winner || "draw"}`));
        match.games.forEach((game) => games.append(fightButton(game))); box.append(games);
      }
      column.append(box);
    }); $("bracket").append(column);
  });
  $("champion").textContent = report.champion;
}
async function replayFight(fight) {
  $("replay-section").hidden = false; $("replay-result").textContent = "Preparing replay…";
  if (playback) playback.stop();
  const robots = fight.entrants.map((name) => ({ name, source: entry(name).source }));
  const result = await battle(await moduleReady, robots, fight.seed, report.limit, 600, { maxFrames: 20000 });
  if (result.error || result.trapped) throw new Error(result.error || result.stderr || "Replay failed");
  if (result.winner !== fight.winner) throw new Error(`Replay winner ${result.winner} differs from recorded ${fight.winner}`);
  $("replay-result").textContent = `Winner: ${result.winner || "draw"} · recorded winner: ${fight.winner || "draw"}`;
  playback = mountBattlePlayback($("replay"), result, 600);
  $("replay-section").scrollIntoView({ behavior: "smooth", block: "start" });
}
function run() {
  if (chosen.length < 3 || chosen.length > 8) { $("status").textContent = "Choose 3 to 8 entrants."; return; }
  const parsedSeed = Number($("seed").value);
  if (!Number.isSafeInteger(parsedSeed) || parsedSeed < 0 || parsedSeed > Number.MAX_SAFE_INTEGER - 256) { $("status").textContent = "Enter a starting number of zero or more."; return; }
  if (worker) worker.terminate();
  $("run").disabled = true; $("results").hidden = true; $("replay-section").hidden = true;
  $("status").textContent = "Starting tournament…";
  const url = new URL(location.href); url.search = new URLSearchParams({ seed: String(parsedSeed), names: chosen.join(",") });
  if (params.get("engine") === "interpreter") url.searchParams.set("engine", "interpreter");
  if (chosen.includes("Your robot")) url.searchParams.set("source", entry("Your robot").source);
  history.replaceState(null, "", url); $("share").replaceChildren();
  const link = cell("a", "Share this starting number and lineup"); link.href = url.href; $("share").append(link);
  worker = new Worker("./worker.js", { type: "module" });
  worker.onmessage = ({ data }) => {
    if (data.progress) $("status").textContent = data.progress;
    if (data.report) { report = data.report; render(report); $("status").textContent = report.error ? friendlyError(report.error) : `${report.fight_count} fights complete.`; $("run").disabled = false; worker.terminate(); worker = null; }
    if (data.error) { $("status").textContent = friendlyError(data.error); $("run").disabled = false; worker.terminate(); worker = null; }
  };
  worker.onerror = (event) => { $("status").textContent = friendlyError(event.message); $("run").disabled = false; worker.terminate(); worker = null; };
  worker.postMessage({ robots: chosen.map((name) => ({ name, source: entry(name).source })), seed: parsedSeed, limit: 60000, engine: params.get("engine") === "interpreter" ? "interpreter" : "compiled" });
}
$("tournament-form").addEventListener("submit", (event) => { event.preventDefault(); run(); });
window.addEventListener("unhandledrejection", (event) => { $("status").textContent = friendlyError(event.reason?.message || String(event.reason)); });
async function init() {
  moduleReady = loadModule();
  const response = await fetch("../robots.json"); if (!response.ok) throw new Error("Could not load robots.json");
  catalog = await response.json();
  const saved = params.get("source") || loadSavedSource(); if (saved) catalog.push({ name: "Your robot", source: saved, origin: "saved", description: "Your saved robot from Challenge or Editor." });
  chosen = requestedNames ? requestedNames.filter((name) => entry(name)).slice(0, 8) : catalog.slice(0, 4).map((r) => r.name);
  renderPicker(); $("status").textContent = "Ready.";
  if (requestedNames?.length) run();
}
init().catch((error) => { $("status").textContent = friendlyError(error.message); });
