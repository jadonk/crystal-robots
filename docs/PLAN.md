# crystal-robots development plan

Drafted 2026-09-09 on the session branch after merging `dev` (no-op: `dev`,
`main` and `trunk` all point at the same commit). This is a living document;
update it as phases land.

Direction set 2026-09-09: the project is migrating from GitLab to Fossil, and
**Fossil + CGI is the primary hosting example**. Direct hosting (`-p PORT`)
and the other interfaces stay in scope but are secondary. The in-progress
compiler work is fixed alongside the migration, not after it.

## 0. Status

| Date | Milestone |
| --- | --- |
| 2026-09-09 | Baseline audit; plan drafted |
| 2026-09-10 | Phase 0 done: wasmer pinned, runtime specs skippable (`-Dwasmer`), stubs retired |
| 2026-09-10 | Phase 1 done: multipass tokenizer in `src/compiler`, all six examples parse, `-t` trace |
| 2026-09-10 | Phase 2 started: tree-walking interpreter with `Host` seam and `NullHost`, `-i` runs robots to a step limit |
| 2026-09-10 | Phase 4 started: WASM emitter handles `puts` with full integer expressions, verified under wasmer |
| 2026-09-10 | Phase 5 skeleton: CGI mode, capability gate, Markdown replies, overview, example and parse pages, `extroot` script, `fossil-skin/mainmenu` |

Spec suite: 51 examples green with `-Dwasmer`.

## 1. Where the code is today (2026-09-09 audit, kept for history)

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

### Phase 1: language front end (the multipass tokenizer)

Decision 2026-09-10: keep and finish the novel design, a **progressive
multipass tokenizer** over reserved Unicode glyphs driven by the existing
regex grammar table. The logic is worked out in `docs/PARSER.md` and proven
by `scripts/multipass_prototype.cr`, which reduces all six example robots to
the Program glyph with correct precedence and associativity. Port it into
`src/compiler`: extend `Type` with the new glyphs, give `Program` per-pass
layers in place of `nxt`, record the producing rule on each node, turn
`Parser.tokenize` into one reduction pass, and rewrite the parser specs
around pass strings. Golden spec: all six examples parse; one spec per rule.
A small semantic pass afterwards resolves identifiers into locals, globals,
constants and user functions and checks builtin arity.

### Phase 2: reference interpreter

Tree-walking interpreter over the AST with integer-only semantics (Int32,
floor division, 0 is false). Introduce a `Host` interface for the builtins
(`scan`, `cannon`, `drive`, `damage`, `speed`, `loc_x`, `loc_y`, `rand`,
`sqrt`, trig, `sleep`, `puts`). The prelude, the interpreter and the WASM
imports all target this one interface. Count instructions so `-l CYCLES` and
cooperative scheduling become possible. `crystal-robots -i examples/*.cr`
runs end to end against a stub host.

### Phase 3: battlefield simulation

Port the physics from the CROBOTS source referenced in the README (Tom
Poindexter's `crobots`), not from memory: 1000x1000 field, motion cycles, acceleration, turning
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

### Phase 5: Fossil + CGI hosting (primary)

Modeled on Ollama-Codex (`https://ollama.openbeagle.org/ollama`) and
GP-Crystal (`.../gp-crystal`), which are the reference deployments on this
host. The shape, item by item:

1. **One binary.** `shards build` produces `bin/crystal-robots` (the shard
   target). The same executable is the CLI, the CGI and any future daemon.
   Mode selection: if `GATEWAY_INTERFACE` is set, serve the CGI request;
   otherwise dispatch on `argv[0]` (so compatibility symlinks such as
   `bin/robots-cgi` or `bin/robots-battle` can select a mode) and then on
   the normal option parser. The session preview builds exactly this target
   from `shard.yml`, so the preview and production run the same binary.
2. **Deploy location.** Fossil serves the repository directly
   (`fossil server --extroot DIR`, or a Fossil CGI file with an `extroot:`
   line); no Apache or nginx in front. The extroot holds a **symlink**
   `robots -> <checkout>/bin/crystal-robots`, the same way Ollama-Codex's
   `/var/www/cgi-bin/ollama-codex` is a symlink to its `bin/`. A rebuild is
   the deploy; the CGI spawns fresh per request. URL: `/ext/robots/...`.
   The repo carries `fossil-skin/mainmenu` with a `Robots /ext/robots/ * {}`
   line so the app is in the Fossil menu.
3. **Login.** `FOSSIL_USER` is the identity and `FOSSIL_CAPABILITIES` the
   permission set, both provided by Fossil; the CGI never handles
   credentials. Gate as GP-Crystal does: `s`/`a` imply everything, `v`
   expands to `eoih`, `u` to `oh`; read routes need `o` or `h`, routes that
   save robots need `i`. The repository's own anonymous/nobody grants decide
   what the public can do, not code.
4. **Emit under the Fossil chrome.** Replies are
   `Content-Type: text/x-markdown` Markdown, so Fossil wraps them in the
   skin, renders Pikchr fences, and applies its own CSP and nonce. The
   battlefield renders as **Pikchr**: the field, robot positions, headings,
   missiles and explosions at a chosen cycle, plus a scoreboard table, the
   way GP-Crystal draws blocks. Forms are plain HTML inside the Markdown.
   Links are built from `SCRIPT_NAME` from its `/ext/` segment onward, so
   they stay correct under `/ext/robots` and under
   `/ext/preview/<session>/`.
5. **Routes.** `GET /` overview and example list; `GET /examples/<name>`
   source plus its parse derivation (the pass trace, the teaching view);
   `POST /compile` errors or the WASM size and the trace;
   `POST /battle` runs one seeded match and renders the Pikchr replay
   (cycle selectable by query parameter) and the outcome; `GET /version`.
6. **Fossil subprocesses.** When the CGI shells out to `fossil` (to read a
   robot from the repo), scrub `GATEWAY_INTERFACE`, `PATH_INFO`,
   `QUERY_STRING` and `REQUEST_METHOD` from the child environment, as both
   reference projects do, or Fossil treats the call as a CGI request.
7. **State.** First version keeps no state between requests. Later
   candidates, in order of preference: robots stored in the repository
   (versioned files or unversioned `fossil uv`), a cookie carrying the
   match seed and robot selection, then the Fossil config table for
   per-user saved robots keyed by `FOSSIL_USER`. All three are compatible
   with the per-request CGI model. (Design notes below.)

**Why "stateless" was said, and what it actually implies.** Fossil starts a
new CGI process per request and buffers the whole reply before sending it.
So nothing lives in memory between requests, and a reply cannot stream.
That rules out a long-running simulation pushing frames to the browser
from the CGI itself. It does not rule out state: cookies, the Fossil
database and files all work. Ollama-Codex gets live updates through a
separate daemon on port 8443 that the CGI cannot provide; if a live replay
is ever wanted here, the same sidecar approach applies. For a deterministic
match that completes in milliseconds, one request that returns the whole
result is simpler and fits Fossil better, which is why it is the first cut.

### Phase 5b: direct hosting and static export (secondary)

`-p PORT` starts an `HTTP::Server` using the same router through the
`Web::HTTP` adapter. `-s DIR` writes the page shell and static assets for
plain file hosting. Running the compiler in the browser via Crystal's wasm32
target remains a later experiment.

### Phase 6: teaching layers

The "peel back a layer" goal: `dot_emitter` (AST to Graphviz, matching
`examples/test.dot`), `crystal_emitter` (AST back to Crystal that compiles
with the prelude), and later `riscv_emitter`. A language reference for the
subset and a port of the CROBOTS manual sections, published by the existing
`crystal docs` pages job.

### Phase 7: GitLab to Fossil migration and housekeeping

- Replace `.gitlab-ci.yml` with `scripts/ci.sh` that any runner (or a
  developer) can execute: shards install, wasmer 4.4.0 pin, build, spec,
  format check, example builds. Keep the GitLab file only as long as the
  mirror exists.
- README: source links point at the Fossil repository; the contributing
  section describes `fossil clone`, branch, commit and the review flow
  instead of GitLab forks and merge requests. Move `.gitignore` rules into
  `.fossil-settings/ignore-glob`.
- Optional: keep the GitHub mirror alive with `fossil git export`.
- `ameba` lint, GPL headers, version bump, installation and usage sections.

## 4. Parser architecture: decided

2026-09-10: option A, the progressive multipass tokenizer using reserved
UTF-8 glyphs and the existing regex grammar table. The unresolved logic is
now written down in `docs/PARSER.md` and demonstrated by
`scripts/multipass_prototype.cr`. The alternative that was offered (a
hand-written recursive-descent parser, of which a "Pratt parser" is the
operator-precedence variant) is dropped.

## 5. Immediate next steps

1. Phase 3: battlefield simulation from the CROBOTS source, as a `Host`,
   with a seeded RNG and a per-cycle trace; `POST /battle` renders it as
   Pikchr under the Fossil chrome.
2. Phase 2 remainder: semantic checks (undefined names, builtin arity)
   reported before running; instruction slicing per robot per cycle.
3. Phase 4 remainder: variables, functions and control flow in the WASM
   emitter, then the differential spec against the interpreter.

## 6. Order of work

Phase 0, then Phase 1 (front end) and the Phase 5 skeleton side by side so
the parse trace is visible in the browser early, then Phases 2 through 4
with `/compile` and `/battle` lighting up as each lands, then Phase 7
migration items, then Phase 5b and Phase 6.
