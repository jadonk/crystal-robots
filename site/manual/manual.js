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
  const { groups, entries } = await response.json();
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
      const description = document.createElement("p");
      description.textContent = `${entry.blurb} Gives back ${entry.returns}. Try: ${entry.example}`;
      detail.append(description);
      const example = document.createElement("pre");
      const code = document.createElement("code");
      const call = entry.name === "scan" ? "puts scan(45, 10)" :
        entry.name === "drive" ? "drive(90, 50)\n  sleep" :
        entry.name === "cannon" ? "distance = scan(45, 10)\n  if distance > 0\n    cannon(45, distance)\n  end" :
        entry.name === "sleep" ? "drive(0, 50)\n  sleep" :
        entry.name === "puts" ? "puts damage" :
        entry.name === "rand" ? "puts rand(360)" :
        entry.name === "sqrt" ? "puts sqrt(25)" :
        entry.name === "sin" ? "puts sin(30)" :
        entry.name === "cos" ? "puts cos(30)" :
        entry.name === "tan" ? "puts tan(30)" :
        entry.name === "atan" ? "puts atan(57735)" : `puts ${entry.name}`;
      code.textContent = `main("Try ${entry.name}") do\n  ${call}\nend`;
      example.append(code); detail.append(example);
      row.append(term, detail);
      list.append(row);
    }
    section.append(list);
    target.append(section);
  }
} catch {
  target.textContent = "The command list could not load. Open the list instead: ";
  const link = document.createElement("a");
  link.href = "../cheat-sheet.json";
  link.textContent = "cheat-sheet.json";
  target.append(link);
}
