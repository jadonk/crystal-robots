// A minimal hand-written WASI preview1 host for crystal-robots' browser
// build (`site/crystal-robots.wasm`, from `src/browser.cr`). No framework,
// no CDN: this implements only the 7 imports that module actually uses
// (confirmed with `wasmer inspect site/crystal-robots.wasm`) -- args_get,
// args_sizes_get, fd_fdstat_get, fd_fdstat_set_flags, fd_write, proc_exit,
// random_get -- not a general-purpose WASI runtime.
//
// Crystal 1.18.2 stubs out exception handling for the `wasm32` target: a
// `raise` inside the module prints its message to stderr and then traps
// (an `unreachable` instruction) instead of unwinding to a `rescue`. That
// aborts the *instance*, not just the call -- a parse error, an
// interpreter step-limit or a WASM_Emitter::Unsupported source all take
// the module down with them. `run` below instantiates fresh every call
// (the compiled `WebAssembly.Module` is reused; only instantiation and
// its linear memory are per-call) so one bad paste can never affect the
// next, and reports a trap as a normal `{error}` result instead of an
// unhandled JS exception.

export class WasiExit extends Error {
  constructor(code) {
    super(`wasi proc_exit(${code})`);
    this.code = code;
  }
}

// Builds the `wasi_snapshot_preview1` import namespace. Call `setMemory`
// with the instance's exported `memory` once it exists (imports must be
// supplied before `WebAssembly.instantiate`, but they only need to touch
// memory once the instance is live).
export function makeWasiImports({ onStdout, onStderr } = {}) {
  let memory;
  const dec = new TextDecoder();

  function view() {
    return new DataView(memory.buffer);
  }

  function readIovs(iovsPtr, iovsLen) {
    const v = view();
    const chunks = [];
    for (let i = 0; i < iovsLen; i++) {
      const base = iovsPtr + i * 8;
      const bufPtr = v.getUint32(base, true);
      const bufLen = v.getUint32(base + 4, true);
      chunks.push(new Uint8Array(memory.buffer, bufPtr, bufLen));
    }
    return chunks;
  }

  const wasi_snapshot_preview1 = {
    args_sizes_get(argcPtr, argvBufSizePtr) {
      const v = view();
      v.setUint32(argcPtr, 0, true);
      v.setUint32(argvBufSizePtr, 0, true);
      return 0;
    },
    args_get(_argvPtr, _argvBufPtr) {
      return 0;
    },
    fd_fdstat_get(_fd, statPtr) {
      const v = view();
      v.setUint8(statPtr, 2); // fs_filetype: character device
      v.setUint16(statPtr + 2, 0, true); // fs_flags
      v.setBigUint64(statPtr + 8, 0xffffffffffffffffn, true); // fs_rights_base
      v.setBigUint64(statPtr + 16, 0xffffffffffffffffn, true); // fs_rights_inheriting
      return 0;
    },
    fd_fdstat_set_flags(_fd, _flags) {
      return 0;
    },
    fd_write(fd, iovsPtr, iovsLen, nwrittenPtr) {
      let total = 0;
      let text = "";
      for (const chunk of readIovs(iovsPtr, iovsLen)) {
        total += chunk.length;
        text += dec.decode(chunk);
      }
      if (fd === 1 && onStdout) onStdout(text);
      if (fd === 2 && onStderr) onStderr(text);
      view().setUint32(nwrittenPtr, total, true);
      return 0;
    },
    proc_exit(code) {
      throw new WasiExit(code);
    },
    random_get(bufPtr, bufLen) {
      crypto.getRandomValues(new Uint8Array(memory.buffer, bufPtr, bufLen));
      return 0;
    },
  };

  return {
    wasi_snapshot_preview1,
    setMemory(m) {
      memory = m;
    },
  };
}

// A fresh instance of `compiledModule`, started and ready for `crd_*`
// calls. Every entry point below gets its own instance -- see the module
// comment in `src/browser.cr` on why a trap must not carry over.
async function instantiate(compiledModule, onStderr) {
  // A box, not a plain local: the trap this is here to report typically
  // happens on a *later* call (`crd_run`/`crd_interpret`, below) than
  // `_start`, so the message arrives on stderr after this function has
  // already returned -- capturing a plain string here would miss it.
  const stderrBox = { text: "" };
  const wasi = makeWasiImports({
    onStderr: (s) => {
      stderrBox.text += s;
      if (onStderr) onStderr(s);
    },
  });
  const instance = await WebAssembly.instantiate(compiledModule, wasi);
  wasi.setMemory(instance.exports.memory);
  try {
    instance.exports._start();
  } catch (e) {
    if (!(e instanceof WasiExit && e.code === 0)) return { trapped: true, stderrBox };
  }
  return { instance, stderrBox };
}

// Writes `source` into a fresh instance and calls `entry` (`crd_run` or
// `crd_interpret`), returning `{ trapped: true, stderr }` on a trap or
// `{ instance, report }` (`report` parsed from `resultPtrFn`/`resultLenFn`)
// otherwise -- the caller reads any further exports (e.g. the emitted
// WASM bytes) from `instance` before it goes out of scope.
async function callEntry(compiledModule, source, entry, resultPtrFn, resultLenFn, onStderr) {
  const started = await instantiate(compiledModule, onStderr);
  if (started.trapped) return { trapped: true, stderr: started.stderrBox.text };
  const { instance, stderrBox } = started;
  const { memory } = instance.exports;
  try {
    const bytes = new TextEncoder().encode(source);
    const ptr = instance.exports.crd_alloc(bytes.length);
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    instance.exports[entry]();
    const rp = instance.exports[resultPtrFn]();
    const rl = instance.exports[resultLenFn]();
    const report = JSON.parse(new TextDecoder().decode(new Uint8Array(memory.buffer, rp, rl)));
    return { instance, report };
  } catch (e) {
    return { trapped: true, stderr: stderrBox.text };
  }
}

// Runs `source` through `crd_run` (derivation, checker report, emitted
// WASM) and, when it checked clean, `crd_interpret` (the interpreter
// trace) -- two separate module instances, so a trap in the interpreter
// (a `while true` fight loop past the step limit, most real robots) never
// erases the derivation and checker report the first call already got.
// Returns the merged report, or `{ trapped: true, stderr }` if `crd_run`
// itself trapped.
export async function run(compiledModule, source, { onStderr } = {}) {
  const first = await callEntry(compiledModule, source, "crd_run", "crd_result_ptr", "crd_result_len", onStderr);
  if (first.trapped) return first;
  const { instance, report } = first;

  if (report.wasm_len) {
    const wp = instance.exports.crd_wasm_ptr();
    const wl = instance.exports.crd_wasm_len();
    report.wasm_bytes = new Uint8Array(instance.exports.memory.buffer.slice(wp, wp + wl));
  }

  if (report.problems.length === 0) {
    const second = await callEntry(
      compiledModule, source, "crd_interpret", "crd_interpret_result_ptr", "crd_interpret_result_len", onStderr,
    );
    report.interpreter = second.trapped ? null : second.report;
  }

  return report;
}
