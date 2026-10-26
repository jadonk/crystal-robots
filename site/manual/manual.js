const toc = document.querySelector("#manual-toc");
const smallScreen = matchMedia("(max-width: 700px)");
function setTocForScreen() {
  toc.open = !smallScreen.matches;
}
setTocForScreen();
smallScreen.addEventListener("change", setTocForScreen);

const target = document.querySelector("#api-groups");
try {
  const response = await fetch("../cheat-sheet.json");
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const { groups, cost, entries } = await response.json();
  target.replaceChildren();
  for (const group of groups) {
    const section = document.createElement("section");
    section.className = "api-group";
    const heading = document.createElement("h3");
    heading.textContent = group;
    section.append(heading);
    const list = document.createElement("dl");
    list.className = "api-list";
    for (const entry of entries.filter((item) => item.group === group)) {
      const row = document.createElement("div");
      const term = document.createElement("dt");
      const signature = document.createElement("code");
      signature.textContent = entry.signature;
      term.append(signature);
      const detail = document.createElement("dd");
      detail.textContent = `${entry.blurb} Returns ${entry.returns}. Costs ${cost} cycles. Example: ${entry.example}`;
      row.append(term, detail);
      list.append(row);
    }
    section.append(list);
    target.append(section);
  }
} catch {
  target.textContent = "The API reference could not load. Open the raw API data instead: ";
  const link = document.createElement("a");
  link.href = "../cheat-sheet.json";
  link.textContent = "cheat-sheet.json";
  target.append(link);
}
