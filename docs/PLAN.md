# crystal-robots development plan

Drafted 2026-09-09 on the session branch after merging `dev` (no-op: `dev`,
`main` and `trunk` all point at the same commit). This is a living document;
update it as phases land.

## 1. Where the code is today

Measured on this checkout with Crystal 1.18.2 and wasmer 4.4.0.

| Check | Result |
| --- | --- |
| `crystal build src/cli.cr` | passes |
| `crystal tool format --check` | passes |
| `crystal build --prelude=../src/prelude examples/counter.cr` | passes and runs |
| `crystal spec` | 25 examples, 7 pass, 18 fail |

What exists:

- **`src/crystal-robots.cr`**: `Robot` model with CROBOTS constants, but every
  sensor/actuator (`scan`, `cannon`, `drive`, ...) is a logging stub. `Missile`
  holds constants only. `Battlefield` is empty. `CLI` parses the CROBOTS-style
  options; `-m`, `-l`, `-p`, `-s` are TODO stubs.
- **`src/prelude.cr`**: the native path. Robots compile with the real Crystal
  compiler against builtins that delegate to the active `Robot`. This works
  end to end today and is the one path with running examples.
- **`src/compiler/compiler.cr`**: `Type` enum (one Unicode glyph per token kind)
  and `Program`, a source string plus an array of `Node(start, count, nxt)`.
  The design is a multi-pass string rewriter: each pass appends token glyphs to
  the source and regexes over the glyph string to reduce it.
- **`src/compiler/parser.cr`**: the grammar table and `tokenize`. Mid-refactor:
  the pass-through branches in `map` are commented `TODO`, and the
  "skip token" path indexes the AST with a source offset, which raises
  `IndexError` for any input with more than one token. This is the root cause
  of most of the spec failures.
- **`src/compiler/interpreter.cr`**: written against an older `Program` API
  (`p.start`, `pc.inc(1)`). It only compiles because nothing calls it.
- **`src/compiler/wasm_emitter.cr`**: chasm-derived binary encoder. Sections are
  hard-coded for one `env.puts` import and one `run` export. `codeFromAst`
  checks the wrong variable for the argument type, so it never emits a const.
- **`crystal_emitter.cr`, `dot_emitter.cr`, `riscv_emitter.cr`**: empty files.
- **`Compiler.compile_to_wasm` / `Compiler.interpret`**: return empty `Bytes`,
  so every emitter and interpreter spec fails regardless of the parser.
- **Web UI / server**: nothing yet. README promises a hosted page with the
  compiler built in.
- **CI (`.gitlab-ci.yml`)**: the test stage installs wasmer via
  `scripts/install_wasmer.sh`, which fetches the latest release. Wasmer 7.x no
  longer ships `linux-musl-amd64`, so on the Alpine image the test stage cannot
  link. Wasmer 4.4.0 is the last release with a musl build and works with
  the pinned `wasmer` shard (0.2.3).

## 2. What the language must support

Inventory of constructs used by the five example robots, which are the
acceptance test for the front end:

- Comments, integer literals, string literals, `true`.
- `main("Name") do ... end`, `global(name, init)`, `def name(a, b) ... end`
  with implicit last-expression return and explicit `return`.
- Uppercase constants, `;`-separated statements on one line (`sniper.cr`).
- Assignment and compound assignment: `=`, `+=`, `-=`, `%=`.
- Arithmetic `+ - * / // %`, comparison `== != < > <= >=`, logical `&& ||`,
  parentheses, unary minus.
- `if / elsif / else / end`, `while ... end`, assignment inside a condition
  (`while (range = scan(a, r)) > 0`).
- Calls to builtins with 0, 1 or 2 args and calls to user functions with
  nested call arguments (`go(rand(1000), rand(1000))`).

Gaps in the current grammar table: no identifiers (any name that is not a
keyword raises "Unexpected token"), no `=` or compound assignment, no `%`,
`/`, `&&`, `||`, `return`, `global`, `sleep`, and `<=`/`>=` collapse into
`<`/`>`.

## 3. Phases

Each phase ends green: focused specs pass, `crystal tool format --check`
passes, and the five examples still build with the prelude.

### Phase 0: stabilize the baseline

1. Pin wasmer to v4.4.0 in CI and document `WASMER_DIR` in the README.
2. Split `spec/spec_helper.cr` so specs that need the wasmer runtime are
   skipped (not link-failed) when the library is absent. `crystal spec` must
   give a signal on a bare machine.
3. Decide the parser architecture (section 4) and record the decision here.
4. Retire the `Compiler.compile_to_wasm` / `interpret` stubs in favor of the
   real pipeline, and bring the 25 existing specs to green or rewrite the
   ones that encoded the abandoned API.

### Phase 1: language front end

Lexer and parser producing an AST for the subset in section 2, with
line:column error messages. A semantic pass resolves names into locals,
globals, constants, user functions and builtins, and checks builtin arity.
Golden spec: all five examples parse; one spec per grammar production.

### Phase 2: reference interpreter

Tree-walking interpreter over the AST with integer-only semantics (Int32,
floor division, 0 is false). Introduce a `Host` interface for the builtins
(`scan`, `cannon`, `drive`, `damage`, `speed`, `loc_x`, `loc_y`, `rand`,
`sqrt`, trig, `sleep`, `puts`). The prelude, the interpreter and the WASM
imports all target this one interface. Count instructions so `-l CYCLES` and
cooperative scheduling become possible. `crystal-robots -i examples/*.cr`
runs end to end against a stub host.

### Phase 3: battlefield simulation

Port CROBOTS physics: 1000x1000 field, motion cycles, acceleration, turning
limit, wall collisions, missile flight, explosion radii and damage, scanner
resolution, reload. Seeded RNG for reproducible matches. Robots execute N
instructions per motion cycle. `-m` runs multiple matches and tallies wins.
Emit a per-cycle trace (JSON) that later feeds the web renderer. Specs cover
distance and heading math, missile damage, and match determinism.

### Phase 4: WASM back end

Emit from the AST: locals, globals, user functions, `if`/`block`/`loop`/
`br_if`, i32 ops, and calls to imported host functions. Bind those imports to
the `Host` interface through wasmer for both the CLI and the specs.
Differential spec: for every example, interpreter trace == WASM trace. Add a
`.wat` text emitter as a debugging aid.

### Phase 5: web UI and hosting

Recommended first cut: `-p PORT` starts an `HTTP::Server` that serves static
assets, compiles submitted sources, runs the simulation server-side and
streams the cycle trace over SSE. The browser renders the field on a canvas
with a scoreboard. `-s DIR` writes the static assets for the pages job.
Revisit running the compiler in the browser via Crystal's wasm32 target once
that toolchain is solid enough. Reviewable through the session preview
deploy before any merge.

### Phase 6: teaching layers

The "peel back a layer" goal: `dot_emitter` (AST to Graphviz, matching
`examples/test.dot`), `crystal_emitter` (AST back to Crystal that compiles
with the prelude), and later `riscv_emitter`. A language reference for the
subset and a port of the CROBOTS manual sections, published by the existing
`crystal docs` pages job.

### Phase 7: housekeeping

README installation and usage sections, `ameba` lint, GPL headers, version
bump, and a CI matrix that runs both the native examples and the spec suite.

## 4. Open decision: parser architecture

Two ways to reach Phase 1.

**A. Finish the string-rewriting design.** Keep `Program` as glyph string plus
`Node` array and complete the pass-through logic in `Parser.map`. It matches
the original exploration ("taking control over a programming language
itself") and keeps the Unicode token glyphs, which are a nice visual for
teaching. Cost: the pass-through and skip logic has been the blocker across
the WIP commits from 2024-11 through 2025-04, precedence is encoded as regex
ordering, and identifiers, assignment and nested calls all need new reduction
rules that are hard to express as flat regexes.

**B. Conventional lexer plus recursive-descent (Pratt) parser to a typed
AST.** Roughly 400 lines of Crystal for the subset in section 2, well
understood, easy to give good error messages, and every emitter (WASM, dot,
Crystal, RISC-V) walks the same tree. The `Type` glyphs can remain as token
kinds so the tokenizer output is still printable the same way. Cost: the
current `Program`/`Parser` code is replaced rather than completed, and the
existing parser specs are rewritten.

Recommendation: **B**. It unblocks Phases 2 through 6, and the teaching value
of "see the tokens, see the tree, see the bytes" is preserved by the dot
emitter. If the exploration of the string-rewriting design matters more than
delivery speed, choose A and budget Phase 1 at two to three times the effort.

## 5. Immediate next steps

1. Phase 0 items 1 and 2 (wasmer pin, skippable wasmer specs). No decision
   needed.
2. Confirm A or B in section 4.
3. Start Phase 1 with the lexer, which is needed under either choice.
