// Decoder for the small module shape emitted by WASM_Emitter. All offsets are
// absolute byte offsets in the module; unfamiliar instructions stay visible.
const sectionNames = ["custom", "type", "import", "function", "table", "memory", "global", "export", "start", "element", "code", "data"];
const opNames = new Map(Object.entries({
  0x02: "block", 0x03: "loop", 0x04: "if", 0x05: "else", 0x0b: "end",
  0x0c: "br", 0x0d: "br_if", 0x0e: "br_table", 0x0f: "return", 0x10: "call", 0x1a: "drop",
  0x20: "local.get", 0x21: "local.set", 0x22: "local.tee",
  0x23: "global.get", 0x24: "global.set", 0x28: "i32.load", 0x36: "i32.store", 0x41: "i32.const",
  0x45: "i32.eqz", 0x46: "i32.eq", 0x47: "i32.ne", 0x48: "i32.lt_s",
  0x4a: "i32.gt_s", 0x4c: "i32.le_s", 0x4e: "i32.ge_s",
  0x6a: "i32.add", 0x6b: "i32.sub", 0x6c: "i32.mul", 0x6d: "i32.div_s",
  0x6f: "i32.rem_s", 0x71: "i32.and", 0x72: "i32.or", 0x73: "i32.xor",
}).map(([key, value]) => [Number(key), value]));
const indexes = new Set([0x0c, 0x0d, 0x10, 0x20, 0x21, 0x22, 0x23, 0x24]);
const blocks = new Set([0x02, 0x03, 0x04]);

function reader(bytes, offset = 0) {
  let pos = offset;
  return {
    get pos() { return pos; },
    seek(next) { pos = next; },
    byte() { if (pos >= bytes.length) throw new Error("Truncated WebAssembly module"); return bytes[pos++]; },
    string() { const length = this.unsigned(); const start = pos; pos += length; return new TextDecoder().decode(bytes.subarray(start, pos)); },
    unsigned() {
      let value = 0, shift = 0, byte;
      do { byte = this.byte(); value += (byte & 0x7f) * 2 ** shift; shift += 7; }
      while (byte & 0x80 && shift < 42);
      if (byte & 0x80) throw new Error("LEB128 value is too long");
      return value;
    },
    signed() {
      let value = 0, shift = 0, byte;
      do { byte = this.byte(); value += (byte & 0x7f) * 2 ** shift; shift += 7; }
      while (byte & 0x80 && shift < 35);
      if (byte & 0x80) throw new Error("LEB128 value is too long");
      if (shift < 32 && (byte & 0x40)) value -= 2 ** shift;
      return value | 0;
    },
  };
}

export function hex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join(" ");
}

export function decodeWasm(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  if (hex(bytes.subarray(0, 8)) !== "00 61 73 6d 01 00 00 00") throw new Error("Expected a WebAssembly v1 module");
  const r = reader(bytes, 8);
  const sections = [];
  while (r.pos < bytes.length) {
    const start = r.pos;
    const id = r.byte();
    const size = r.unsigned();
    const payloadStart = r.pos;
    const end = payloadStart + size;
    if (end > bytes.length) throw new Error("Section extends past end of module");
    const section = { id, name: sectionNames[id] || `section ${id}`, start, payloadStart, end, size, bodies: [], entries: [] };
    if (id === 5) {
      const sr = reader(bytes, payloadStart);
      for (let i = 0, count = sr.unsigned(); i < count; i++) {
        const flags = sr.unsigned(), minimum = sr.unsigned();
        const maximum = flags & 1 ? sr.unsigned() : null;
        section.entries.push(`memory ${i}: at least ${minimum} pages${maximum === null ? "" : `, at most ${maximum} pages`}`);
      }
    }
    if (id === 6) {
      const sr = reader(bytes, payloadStart);
      for (let i = 0, count = sr.unsigned(); i < count; i++) {
        const type = sr.byte(), mutable = sr.byte();
        const opcode = sr.byte();
        if (opcode !== 0x41) throw new Error("Unsupported global initializer");
        const initial = sr.signed();
        if (sr.byte() !== 0x0b) throw new Error("Unterminated global initializer");
        section.entries.push(`global ${i}: ${type === 0x7f ? "number" : `type ${type}`}, ${mutable ? "changeable" : "fixed"}, starts at ${initial}`);
      }
    }
    if (id === 7) {
      const sr = reader(bytes, payloadStart);
      const kinds = ["function", "table", "memory", "global"];
      for (let i = 0, count = sr.unsigned(); i < count; i++) {
        const name = sr.string(), kind = sr.byte(), index = sr.unsigned();
        section.entries.push(`${name}: ${kinds[kind] || `kind ${kind}`} ${index}`);
      }
    }
    if (id === 10) {
      const cr = reader(bytes, payloadStart);
      const count = cr.unsigned();
      for (let i = 0; i < count; i++) {
        const bodyStart = cr.pos;
        const bodySize = cr.unsigned();
        const codeStart = cr.pos;
        const bodyEnd = codeStart + bodySize;
        if (bodyEnd > end) throw new Error("Function body extends past code section");
        const localGroupCount = cr.unsigned();
        const locals = [];
        for (let group = 0; group < localGroupCount; group++) {
          locals.push({ count: cr.unsigned(), type: cr.byte() });
        }
        const instructions = [];
        while (cr.pos < bodyEnd) {
          const at = cr.pos;
          const opcode = cr.byte();
          const mnemonic = opNames.get(opcode) || "unknown";
          let operand = null;
          if (indexes.has(opcode)) operand = cr.unsigned();
          else if (opcode === 0x0e) {
            const count = cr.unsigned();
            const targets = Array.from({ length: count }, () => cr.unsigned());
            operand = `${targets.join(", ")} · default ${cr.unsigned()}`;
          }
          else if (opcode === 0x28 || opcode === 0x36) operand = `align ${cr.unsigned()}, offset ${cr.unsigned()}`;
          else if (opcode === 0x41) operand = cr.signed();
          else if (blocks.has(opcode)) {
            const type = cr.byte();
            operand = type === 0x40 ? "void" : type === 0x7f ? "i32" : `0x${type.toString(16)}`;
          }
          instructions.push({ start: at, end: cr.pos, mnemonic, operand, hex: hex(bytes.subarray(at, cr.pos)) });
        }
        section.bodies.push({ index: i, start: bodyStart, end: bodyEnd, locals, instructions });
      }
      if (cr.pos !== end) throw new Error("Code section length mismatch");
    }
    sections.push(section);
    // Sections other than code are presented with their byte ranges and hex.
    r.seek(end);
  }
  return { header: { start: 0, end: 8, magic: "\0asm", version: 1 }, sections, byteLength: bytes.length };
}

export function renderWasm(container, input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  const module = decodeWasm(bytes);
  container.replaceChildren();
  const heading = document.createElement("p");
  heading.textContent = `${module.byteLength.toLocaleString()} bytes · WebAssembly v1`;
  container.append(heading);
  const header = document.createElement("pre");
  header.textContent = `00000000–00000007  header  ${hex(bytes.subarray(0, 8))}`;
  container.append(header);
  for (const section of module.sections) {
    const details = document.createElement("details");
    details.open = section.id === 10;
    const summary = document.createElement("summary");
    summary.textContent = `${section.name} · section ${section.id} · bytes ${section.start}–${section.end - 1} (${section.size} payload bytes)`;
    details.append(summary);
    const raw = document.createElement("pre");
    raw.className = "wasm-hex";
    raw.textContent = hex(bytes.subarray(section.start, section.end));
    details.append(raw);
    if (section.entries.length) {
      const entries = document.createElement("pre");
      entries.className = "wasm-listing";
      entries.textContent = section.entries.join("\n");
      details.append(entries);
    }
    for (const body of section.bodies) {
      const title = document.createElement("h4");
      title.textContent = `Function body ${body.index + 1} · bytes ${body.start}–${body.end - 1}`;
      details.append(title);
      const listing = document.createElement("pre");
      listing.className = "wasm-listing";
      listing.textContent = body.instructions.map((op) =>
        `${String(op.start).padStart(6)}  ${op.hex.padEnd(16)}  ${op.mnemonic}${op.operand === null ? "" : ` ${op.operand}`}`,
      ).join("\n");
      details.append(listing);
    }
    container.append(details);
  }
  return module;
}
