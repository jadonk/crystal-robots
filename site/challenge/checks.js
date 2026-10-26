import { decodeFrames } from "../battle-playback.js";

export function evaluateBattle(level, report) {
  const { frames, missileSlots } = decodeFrames(report.frameBuffer);
  const first = frames[0].robots[0], last = frames.at(-1).robots[0];
  const distance = Math.hypot(last.x - first.x, last.y - first.y);
  const fired = frames.some((frame) => frame.robots[0].fired || frame.missiles.slice(0, missileSlots).some((missile) => missile.present));
  const targetDamage = report.robots[1]?.damage || 0;
  const won = report.winner === "Your robot";
  if (level === 1) return { pass: distance > 100, reason: `Your robot moved ${Math.round(distance)} m; the goal is more than 100 m.` };
  if (level === 2) return { pass: fired, reason: fired ? "Your robot fired a missile after looking for the target." : "No missile appeared; scan for the target and fire when you find it." };
  if (level === 3) return { pass: targetDamage > 0, reason: targetDamage > 0 ? `The target took ${targetDamage}% damage.` : "The target took no damage; adjust your aim or range." };
  if (level === 4) return { pass: won && targetDamage >= 100, reason: won && targetDamage >= 100 ? "You destroyed the target before time runs out." : `The target finished with ${targetDamage}% damage; destroy it to pass.` };
  return { pass: won, reason: won ? "Your robot won this fight." : `This fight went to ${report.winner || "a draw"}.` };
}
export function evaluateSeries(wins, opponent) {
  return { pass: wins >= 2, reason: `Your robot beat ${opponent} in ${wins} of 3 fights; 2 wins are needed.` };
}
export function evaluateTournament(report) {
  const reached = report.rounds?.some((round) => round.matches.some((match) => match.entrants.includes("Your robot"))) || false;
  return { pass: reached, reason: reached ? (report.champion === "Your robot" ? "You reached the final rounds and won the tournament. Badge of honor!" : "You reached the final rounds; win it for the badge of honor.") : "Your robot did not reach the final rounds; improve it and try again." };
}
