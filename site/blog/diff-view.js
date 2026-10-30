// Small, dependency-free renderer for the chapter's selected changes.
const url = (id) => `./diffs/${encodeURIComponent(id)}.json`;
const link = (sha) => `https://github.com/jadonk/crystal-robots/commit/${sha}`;
const element = (tag, className, content) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
};
const linkedNote = (value) => {
  const fragment = document.createDocumentFragment();
  const pattern = /\[\[([^|\]]+)\|(#crystal-[a-z-]+)\]\]/g;
  let start = 0;
  for (const match of value.matchAll(pattern)) {
    fragment.append(value.slice(start, match.index));
    const a = element("a", "", match[1]);
    a.href = match[2];
    fragment.append(a);
    start = match.index + match[0].length;
  }
  fragment.append(value.slice(start));
  return fragment;
};
const tokens = (source, file) => {
  const pattern = /(<\/?[A-Za-z][^>]*>|^\s*[\w.-]+(?=\s*:)|#.*$|\/\/.*$|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:require|def|end|class|module|do|if|else|elsif|when|while|until|return|describe|it|should|abstract|struct|getter|private|case|true|false|nil|const|let|function|import|export|from|git|crystal|shards)\b|\b\d+\b|:[a-z_]+\b|\$[A-Za-z_][\w]*)/gm;
  const fragment = document.createDocumentFragment();
  let start = 0;
  for (const match of source.matchAll(pattern)) {
    if (match.index > start) fragment.append(source.slice(start, match.index));
    const value = match[0];
    const kind = value.startsWith("<") && file.endsWith(".html") ? "keyword"
      : /^(#|\/\/)/.test(value) ? "comment"
      : /^("|')/.test(value) ? "string"
      : /^\d/.test(value) ? "number"
      : /^:|^\$/.test(value) ? "symbol" : "keyword";
    fragment.append(element("span", `syntax-${kind}`, value));
    start = match.index + value.length;
  }
  fragment.append(source.slice(start));
  return fragment;
};
function renderLines(rows, lines, notes, file) {
  for (const line of lines) {
    const tr = element("tr", `diff-${line.kind === "+" ? "add" : line.kind === "-" ? "remove" : "context"}`);
    tr.setAttribute("aria-label", `${line.kind === "+" ? "Added" : line.kind === "-" ? "Removed" : "Unchanged"} line: ${line.text}`);
    const old = element("td", "diff-number", line.old ?? "");
    const next = element("td", "diff-number", line.new ?? "");
    const code = element("td", "diff-code");
    code.append(element("span", "diff-mark", line.kind));
    code.append(tokens(line.text, file));
    tr.append(old, next, code);
    rows.append(tr);
    for (const [anchor, note] of Object.entries(notes)) {
      if (line.text.includes(anchor)) {
        const callout = element("tr", "diff-callout");
        const cell = element("td", "");
        cell.append(linkedNote(note));
        cell.colSpan = 3;
        callout.append(cell);
        rows.append(callout);
      }
    }
  }
}
function render(view, data) {
  view.replaceChildren();
  view.append(element("p", "diff-summary", data.summary));
  const heading = element("p", "diff-files-heading", "Files changed");
  view.append(heading);
  const files = element("ul", "diff-files");
  for (const file of data.files) {
    const item = element("li", "");
    item.append(element("code", "", file.path), ` — ${file.role} `);
    item.append(element("span", "diff-count", `+${file.added} −${file.removed}`));
    files.append(item);
  }
  view.append(files);
  for (const excerpt of data.excerpts) {
    const block = element("div", "diff-excerpt");
    const note = element("p", "diff-note");
    note.append(linkedNote(excerpt.note));
    block.append(note);
    block.append(element("p", "diff-file", excerpt.file));
    const scroller = element("div", "diff-scroll");
    scroller.tabIndex = 0;
    scroller.setAttribute("aria-label", `Code change in ${excerpt.file}; scroll sideways for long lines`);
    const table = element("table", "diff-table");
    const caption = element("caption", "sr-only", `Selected changed lines in ${excerpt.file}. First number is the old line, second is the new line.`);
    const body = element("tbody", "");
    const before = element("tbody", "diff-extra");
    const after = element("tbody", "diff-extra");
    before.hidden = after.hidden = true;
    renderLines(before, excerpt.before, {}, excerpt.file);
    renderLines(body, excerpt.lines, excerpt.line_notes, excerpt.file);
    renderLines(after, excerpt.after, {}, excerpt.file);
    table.append(caption, before, body, after);
    scroller.append(table);
    block.append(scroller);
    if (excerpt.before.length || excerpt.after.length) {
      const button = element("button", "diff-toggle", "Show more context");
      button.type = "button";
      button.setAttribute("aria-expanded", "false");
      button.addEventListener("click", () => {
        const expanded = button.getAttribute("aria-expanded") === "true";
        before.hidden = after.hidden = expanded;
        button.setAttribute("aria-expanded", String(!expanded));
        button.textContent = expanded ? "Show more context" : "Show less context";
      });
      block.append(button);
    }
    view.append(block);
  }
  const whole = element("a", "diff-whole", "See the whole change on GitHub");
  whole.href = link(data.sha);
  view.append(whole);
}
async function load(view) {
  try {
    const response = await fetch(url(view.dataset.diff));
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(view, await response.json());
  } catch (error) {
    // Existing prose and the link in the HTML remain readable.
    view.dataset.error = "true";
  }
}
const views = document.querySelectorAll(".diff-view[data-diff]");
if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      load(entry.target);
    }
  }, { rootMargin: "600px 0px" });
  views.forEach((view) => observer.observe(view));
} else {
  views.forEach(load);
}
