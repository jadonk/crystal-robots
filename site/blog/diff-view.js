// Small, dependency-free renderer for the chapter's selected changes.
const url = (id) => `./diffs/${encodeURIComponent(id)}.json`;
const link = (sha) => `https://github.com/jadonk/crystal-robots/commit/${sha}`;
const element = (tag, className, content) => {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
};
// Notes may hold [[text|#crystal-term]] links and `code` spans.
const linkedNote = (value) => {
  const fragment = document.createDocumentFragment();
  const pattern = /\[\[([^|\]]+)\|(#(?:crystal|word)-[a-z-]+)\]\]|`([^`]+)`/g;
  let start = 0;
  for (const match of value.matchAll(pattern)) {
    fragment.append(value.slice(start, match.index));
    if (match[3] !== undefined) {
      fragment.append(element("code", "", match[3]));
    } else {
      const a = element("a", "", match[1]);
      a.href = match[2];
      fragment.append(a);
    }
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
function renderLines(rows, lines, file, singleColumn, showMarks) {
  for (const line of lines) {
    const tr = element("tr", `diff-${line.kind === "+" ? "add" : line.kind === "-" ? "remove" : "context"}`);
    tr.setAttribute("aria-label", `${line.kind === "+" ? "Added" : line.kind === "-" ? "Removed" : "Unchanged"} line: ${line.text}`);
    const old = element("td", "diff-number", line.old ?? "");
    const next = element("td", "diff-number", line.new ?? "");
    const code = element("td", "diff-code");
    const source = element("span", "diff-source");
    if (showMarks) source.append(element("span", "diff-mark", line.kind));
    source.append(tokens(line.text, file));
    code.append(source);
    if (singleColumn) tr.append(line.kind === "-" ? old : next, code);
    else tr.append(old, next, code);
    rows.append(tr);
  }
}
function render(view, data) {
  view.replaceChildren();
  view.append(element("p", "diff-summary", data.summary));
  const disclosure = element("details", "diff-files-disclosure");
  disclosure.append(element("summary", "diff-files-heading", `Files changed (${data.files.length})`));
  const files = element("ul", "diff-files");
  for (const file of data.files) {
    const item = element("li", "");
    item.append(element("code", "", file.path), ` — ${file.role} `);
    item.append(element("span", "diff-count", `+${file.added} −${file.removed}`));
    files.append(item);
  }
  disclosure.append(files);
  view.append(disclosure);
  for (const excerpt of data.excerpts) {
    const block = element("div", "diff-excerpt");
    const note = element("p", "diff-note");
    note.append(linkedNote(excerpt.note));
    block.append(note);
    const allAdded = [...excerpt.before, ...excerpt.lines, ...excerpt.after].every((line) => line.kind === "+");
    const allRemoved = [...excerpt.before, ...excerpt.lines, ...excerpt.after].every((line) => line.kind === "-");
    const singleColumn = allAdded || allRemoved;
    const label = allAdded ? (excerpt.lines.some((line) => line.new === 1) ? "new file" : "new code") : allRemoved ? "removed code" : "";
    block.append(element("p", "diff-file", `${excerpt.file}${label ? ` · ${label}` : ""}`));
    const scroller = element("div", "diff-scroll");
    scroller.tabIndex = 0;
    scroller.setAttribute("aria-label", `Code change in ${excerpt.file}`);
    const table = element("table", `diff-table${singleColumn ? " diff-single" : ""}`);
    const columns = element("colgroup", "");
    for (let i = 0; i < (singleColumn ? 1 : 2); i++) columns.append(element("col", "diff-number-column"));
    columns.append(element("col", "diff-code-column"));
    const caption = element("caption", "sr-only", `Selected changed lines in ${excerpt.file}. ${singleColumn ? "One line number per line." : "First number is the old line, second is the new line."}`);
    const body = element("tbody", "");
    const before = element("tbody", "diff-extra");
    const after = element("tbody", "diff-extra");
    before.hidden = after.hidden = true;
    renderLines(before, excerpt.before, excerpt.file, singleColumn, !singleColumn);
    renderLines(body, excerpt.lines, excerpt.file, singleColumn, !singleColumn);
    renderLines(after, excerpt.after, excerpt.file, singleColumn, !singleColumn);
    table.append(caption, columns, before, body, after);
    scroller.append(table);
    block.append(scroller);
    for (const [anchor, explanation] of Object.entries(excerpt.line_notes)) {
      const line = excerpt.lines.find((item) => item.text.includes(anchor));
      const callout = element("p", "diff-callout");
      callout.append(element("span", "diff-callout-label", `Line ${line.new ?? line.old}: `), linkedNote(explanation));
      block.append(callout);
    }
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
