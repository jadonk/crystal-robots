import { check } from "../wasi-shim.js";
import { friendlyError } from "../friendly-errors.js";
import { saveSource } from "../robot-store.js";

export function createEditorSurface({ sourceEl, gutterEl, problemsEl, cheatEl, moduleReady }) {
  function renderGutter() {
    const count = Math.max(1, sourceEl.value.split("\n").length);
    if (gutterEl.children.length !== count) {
      gutterEl.replaceChildren();
      for (let i = 1; i <= count; i++) {
        const li = document.createElement("li"); li.textContent = String(i); gutterEl.append(li);
      }
    }
    for (const li of gutterEl.children) { li.classList.remove("error"); li.removeAttribute("title"); }
    gutterEl.scrollTop = sourceEl.scrollTop;
  }
  function mark(line, message) {
    const li = gutterEl.children[line - 1];
    if (li) { li.classList.add("error"); li.title = message; }
  }
  new ResizeObserver(() => { gutterEl.style.height = `${sourceEl.clientHeight}px`; }).observe(sourceEl);
  sourceEl.addEventListener("scroll", () => { gutterEl.scrollTop = sourceEl.scrollTop; });
  let timer;
  sourceEl.addEventListener("input", () => {
    renderGutter(); saveSource(sourceEl.value);
    clearTimeout(timer); timer = setTimeout(() => runCheck().catch((e) => { problemsEl.textContent = e.message; }), 500);
  });
  async function runCheck() {
    renderGutter();
    const report = await check(await moduleReady, sourceEl.value);
    if (report.trapped || report.error || report.problems?.length) {
      problemsEl.className = "bad";
      if (report.error) { mark(report.error.line, friendlyError(report.error.message)); problemsEl.textContent = `Code problem: ${friendlyError(report.error.message)}`; }
      else if (report.trapped) problemsEl.textContent = `Could not check this code: ${friendlyError(report.stderr || "(no message)")}`;
      else { report.problems.forEach((p) => mark(p.line, friendlyError(p.message))); problemsEl.textContent = report.problems.map((p) => `${friendlyError(p.message)} at line ${p.line}, column ${p.col}`).join("\n"); }
    } else { problemsEl.className = "ok"; problemsEl.textContent = "Ready to fight: names and the numbers passed to commands look right."; }
    return report;
  }
  async function loadCheatSheet() {
    try {
      const response = await fetch("../cheat-sheet.json");
      if (!response.ok) throw new Error(`fetch cheat-sheet.json: ${response.status}`);
      const sheet = await response.json();
      cheatEl.replaceChildren();
      const title = document.createElement("h2"); title.textContent = "Cheat sheet"; cheatEl.append(title);
      sheet.groups.forEach((group) => {
        const div = document.createElement("div"); div.className = "group";
        const h3 = document.createElement("h3"); h3.textContent = group; div.append(h3);
        const ul = document.createElement("ul");
        sheet.entries.filter((e) => e.group === group).forEach((e) => {
          const li = document.createElement("li");
          const sig = document.createElement("code"); sig.textContent = e.signature; li.append(sig);
          li.append(document.createTextNode(` — ${e.blurb} Gives back ${e.returns}. Try: `));
          const ex = document.createElement("code"); ex.textContent = e.example; li.append(ex); ul.append(li);
        });
        div.append(ul); cheatEl.append(div);
      });
    } catch (e) { cheatEl.textContent = `Could not load cheat sheet: ${e.message}`; }
  }
  return { renderGutter, runCheck, loadCheatSheet };
}
