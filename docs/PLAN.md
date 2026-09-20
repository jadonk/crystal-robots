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
| **[tried 2026-09-14]** 2026-09-10 | Phase 5 skeleton: CGI mode, capability gate, Markdown replies, overview, example and parse pages, `extroot` script, `fossil-skin/mainmenu` |

| **[tried 2026-09-14]** 2026-09-10 | Phase 3 done: CROBOTS battlefield ported from `motion.c`, `intrins.c`, `main.c` as `Battle::Field`; robots interleave one interpreter step at a time in fibers; seeded, deterministic, with a frame trace |
| 2026-09-10 | `-m MATCHES --seed N -l CYCLES` runs matches from the CLI; `GET /battle` renders any frame of a match in Pikchr under the Fossil chrome |
| 2026-09-10 | Preview verified by the user at `/ext/preview/session-<root>/`; the parse form's POST went to the site root because Fossil does not rewrite raw HTML `action` attributes; fixed by using the full `SCRIPT_NAME` |

| 2026-09-10 | Phase 2 remainder: `Compiler::Checker` reports undefined names, call arity, misplaced `return`/`break` and duplicate `def` with locations; the battlefield, `-t`, `-i` and the web pages use it |
| **[tried 2026-09-14]** 2026-09-10 | Battle page takes a pasted robot ("yours") and draws each robot's trail over the frames so far |

| 2026-09-10 | Phase 4 done: the WASM emitter covers globals, constants, locals, user functions of any arity, if/elsif/else, while/until/break, case/when, all builtins as `env` imports, floored `//` and `%` with CROBOTS's divide-by-zero-is-zero; every example compiles; differential specs run three terminating robots under wasmer and the interpreter with the same scripted host and compare output and builtin call logs |

| 2026-09-10 | Review fixes from the trunk-ops merge of 39d4b976: user text can no longer close a code fence or inject markup (fence sized to the text, prose escaped), parse is POST only, request body capped at 64 KB before allocation, source capped at 20 KB, parser pass budget of 20000, invalid UTF-8 and any other failure answer 400/500 instead of crashing, menu and extroot use `/ext/crystal-robots`, `/docs/` no longer ignored for the git mirror |

| 2026-09-10 | Review fixes from the trunk-ops merge of 85c46a57: the interpreter's shared puts buffer is off for battle hosts and capped elsewhere; a robot fiber rescues everything, marks the robot failed and unwinds; repeated runtime errors also fail the robot; a call-depth limit turns unbounded recursion into a runtime error; angle normalization and integer ops are overflow-safe |
| **[tried 2026-09-14]** 2026-09-10 | Battle page reordered (replay on top, static frame, result at the bottom) and given a smooth replay: one SVG with native SMIL animation over 400 keyframes, no script, inside the Fossil chrome |

| **[tried 2026-09-14]** 2026-09-10 | Review fixes from the trunk-ops merge of cdc29f87/61905033: the parser no longer re-copies the whole source every pass (append-only parts, joined lazily) and has a total-glyph work budget of two million on top of the pass budget, so cost is bounded by work done, not by input length alone; parse and battle require a named login (anonymous and nobody are refused with a Markdown 403) until the parser is opened up again; `fossil-skin/mainmenu` restored (my edit had truncated it); replay runs at a chosen frames-per-second (`fps=`, default 20) instead of a fixed duration, and trails grow with the robot instead of predicting its path |

| 2026-09-10 | Cycle model: the interpreter charges CROBOTS-style cycles (fetch/const 1, operator 1, store 1, builtin 2, call 3, branch 1, statement 1; `Interpreter::Costs`, configurable, `Costs.statements` is the old one-per-statement model) and the emitter can insert `env.tick(n)` at the same points (`-c --ticks`); differential specs show both engines charge identical totals on the test robots |
| **[tried 2026-09-14]** 2026-09-10 | Saved robots: wiki pages named `robot/<name>` whose single code block is the source appear on the overview, on the battle form (`w=` parameter) and at `/wiki/<name>`; read through `fossil wiki list/export` with the CGI environment scrubbed |
| 2026-09-10 | The examples list is generated at compile time from `examples/*.cr` by a macro; adding a file is enough |

| **[tried 2026-09-14]** 2026-09-10 | Review fixes from the trunk-ops merge of 6e876706/58ba5789: the parse page parses once under the budgets and renders the passes it holds, elided to 60 lines of at most 300 glyphs, so the error path can no longer run unbounded; budget errors point at the parser's last reduction instead of 1:1; `fossil-skin/mainmenu` mirrors the deployed skin (Agents, Docs, Run for readers); the overview tells anonymous visitors up front that parse and battle need a login and the login links return to the page (`/login?g=`); the hot-loop 1000-term paste could not be reproduced (chains, nested parentheses and call chains all finish in 1 to 6 s at the 500k limit) |

| **[tried 2026-09-14]** 2026-09-10 | Wiki robots hardened: sources over 20 KB are ignored, page names must be plain (letters, digits, space, `_ . -`, at most 40 characters) and are escaped in headings, tables and Pikchr labels anyway, the wiki view needs a login, and every wiki read needs Fossil's wiki-read capability (`j`) |

| **[tried 2026-09-14]** 2026-09-10 | Five saved-robot wiki pages ship in `robots/*.md` (hunter, circler, dodger, wallhugger, turret) with `scripts/publish_wiki_robots.sh` to create or update them; each is spec-tested to parse, pass the checker and hit a target placed 200 m away; discovery: the overview lists saved robots with descriptions and fight links, the battle picker pre-checks a robot from a `pick=` link and links to every robot's view, and the wiki view page offers fight, pick-opponents and edit links; `Battle::Field` accepts fixed start positions |

| **[tried 2026-09-14]** 2026-09-10 | Replay pace is now CROBOTS cycles per second (`cps=`, default 300: a motion update every 50 ms, a full-speed robot crosses the field in about seven seconds, a missile covers its range in under a second), screen time proportional to cycles; default web cycle limit 60k; `matches=` runs a series like `crobots -m` with a wins/ties score table and a replay link per match, capped at 10 matches and 600k cycles of work |

| 2026-09-11 | Phase 7, from the coordinator's answers: versioned `.fossil-settings/ignore-glob` with `.gitignore` as mirror (1ca7c7ed); `scripts/ci.sh` as the one gate command, `--with-wasmer` installs 4.4.0 under the checkout (b980ca71); `build-docs` subcommand embeds `crystal docs` output, served at `/ext/crystal-robots/docs` (2daa7da4); README points at Fossil with mirrors read-only, Fossil contributing flow, `.gitlab-ci.yml` delegates to ci.sh (dda76b7f); **[try]** permissions on capability letters: o/h read, i battle and parse, j saved robots (af515555) |

| **[tried 2026-09-14]** 2026-09-11 | Maintainer review notes (trunk-ops thread): saved robots are read in ONE `fossil sql --readonly` query (latest `robot/*` wiki artifacts as hex, W card parsed in-process), no per-robot export and nothing cached across requests; the API docs are served inside the Fossil chrome (body extracted, scripts and search dropped, inline scoped styles, `fossil-doc` wrapper, doc comments intact) instead of crystal-docs' own UI whose inline script the CSP blocks, aligned with the Ollama-Codex docs CGI; Fossil's versioned `manifest` setting keeps `manifest.uuid` in checkouts and tarballs, embedded at compile time, and `--version` and `/version` report `crystal-robots 0.0.1 (check-in <hash>)` so a deploy can be compared with trunk |

| **[tried 2026-09-14]** 2026-09-11 | Gate regression fix (trunk-ops on `4f6581bb`): the single-query listing split each SQL row at the FIRST space, so any `robot/*` page name with a space — live or a deleted one's leftover tag — crashed the overview, battle and wiki routes for everyone; rows now split at the LAST space (the hex payload never contains one), covered by a spec with a space-named robot and a deleted space-named tag asserting `/`, `/battle` and `/wiki/<name>` stay 200. Also from the same review: a failed `fossil sql` now raises instead of rendering an empty 200 listing; the docs sanitizer strips script tags case-insensitively plus event attributes and `javascript:` links as defense in depth; `search-index.js`/`index.json` are no longer embedded (the search UI they back is already stripped); `scripts/ci.sh` refuses the release `shards build` when `manifest.uuid` is missing or empty (a plain `crystal build` outside ci.sh still falls back to "unknown" for local dev) |

| 2026-09-17 | Maintainer correction and expansion of Phase 6: the AST-once-built diagram is a third view, distinct from the existing parse-in-progress derivation and the planned interpreter-walk diagram; `crystal_emitter` must round-trip (source → AST → `crystal_emitter` → recompile → identical behavior), a bar that must keep holding once GPCR (a future Crystal-subset DSL, additive to crystal-robots's own syntax) exists; battlefield-visual, execution-stepping and browser-editor backlog items opened (see "Phase 6 correction and expansion" below and the [Backlog](/wiki?name=Backlog) wiki page) |

| 2026-09-19 | Phase 5b-1 done: `src/browser.cr` compiles for `wasm32-unknown-wasi` (`scripts/install_wasm32_wasi_libs.sh` pins wasm32-wasi-libs 0.0.3, `scripts/ci.sh --with-wasm32` builds `site/crystal-robots.wasm`, 716 KB release); `site/index.html`+`app.js`+`wasi-shim.js` run it in a static page, no framework, no CDN; `examples/test.cr` round-trips tokens/checker/interpreter/WASM bytes identical to the native CLI; spike finding that reshaped the design: Crystal 1.18.2 has no working exceptions on `wasm32` at all (any `raise` traps the module immediately, confirmed by testing), so `crd_run` and `crd_interpret` are separate calls and the shim reinstantiates per call; `.github/workflows/pages.yml` deploys to jadonk.github.io/crystal-robots on push to `main`, gated on Pages being enabled (source: GitHub Actions); live and verified at [jadonk.github.io/crystal-robots](https://jadonk.github.io/crystal-robots/) |

| 2026-09-20 | Phase 5b-2 done: battle entirely in the browser, no server (deferred by Phase 5b-1). `src/battle/step_robot.cr` gives `Battle::Robot` a second, non-fiber execution path (`start_stepwise`/`step!`) that runs the interpreter's own tree-walk in continuation-passing style, pausing after exactly one charged CROBOTS cycle — the same granularity `field.cr`'s fiber/`Channel` gives the native path — without `spawn`, `Fiber` or ever calling `raise`; `Field#run_stepwise` drives it with the same physics `run` already has. `Compiler::Parser` gains non-raising `try_parse`/`try_lex` (returning the `Error` instead of raising it) so a bad robot's parse failure can be reported as data instead of trapping the module; `parse`/`lex` are unchanged, thin wrappers over them. **Maintainer correction, same day:** no canvas/JS renderer — `src/web/cgi.cr`'s `svg_animation` (the served `/battle` page's SMIL-animated SVG) moved to `src/battle/svg_replay.cr` as `Battle.svg_animation`, a plain function of a finished `Field`; `cgi.cr` now delegates to it (`ROBOT_COLORS`/`ANIM_CPS` likewise point at the shared constants), one renderer for both surfaces. `src/browser.cr` exports `crd_battle_alloc`/`crd_battle_run`/`crd_battle_result_*`: one JSON request (2 to 4 `{name, source}` robots, a seed, a cycle limit clamped to CROBOTS's own `[MOTION_CYCLES, CYCLE_LIMIT]`, a replay `cps`), one JSON report — standings plus the rendered SVG string; the per-cycle frame log stays inside the call, never crosses into JS. `site/wasi-shim.js`'s `battle()` takes the same inputs; `site/battle.js` (new, no framework, no CDN) only collects them and inserts the returned SVG — no drawing code of its own. `site/robots.json` (the picker's bundled examples, from `examples/*.cr`) is generated by `scripts/build_robots_json.cr`, called from `.github/workflows/pages.yml` directly rather than `scripts/ci.sh`: ci.sh is being replaced by `ci.cr` on a parallel branch (ticket feebeb1531), so a new build step lands beside it, not inside it, until that merges. `spec/wasm32_spec.cr` compares a seeded battle's standings, cycle count and rendered SVG text against `Battle::Field#run_stepwise` + `Battle.svg_animation` run natively — the same source compiled for both targets, the same cross-compilation-fidelity check Phase 5b-1's own cases make for `crd_run`/`crd_interpret` — and confirms a robot with a parse error is reported inactive with its `error`, isolated, not a trap. Manually verified end to end: a 4-robot native run and the same request driven through node + the real `site/wasi-shim.js` produce byte-identical JSON reports (SVG included); a deliberately bad robot source alongside a good one reports `{active: false, error: "Cannot reduce..."}` for the bad one and a winner among the rest, no trap; the page loads and a battle runs to completion with the SVG replay rendering correctly (headless Chrome screenshot, no console errors). |

Spec suite: 101 examples green with `-Dwasmer`; `scripts/ci.sh --with-wasmer` green end to end; `scripts/ci.sh --with-wasm32` green end to end (Phase 5b-1, Phase 5b-2).

**WASM robots on the battlefield, decided.** Cycle ticks are injected at
every operation and builtin call in both engines (above), so a WASM robot
reports the same cycle count as the interpreter would. Interleaving it on
the field needs the `tick` host call to hand control back to the
scheduler. That means blocking inside a wasmer host callback while another
fiber runs; whether the wasmer 4 runtime tolerates a fiber switch inside a
host call is the open question to spike (a wasmer-backed `Battle::Robot`
behind the same `cycle`/`stop` protocol). The ideal, as noted in the
thread, is a runtime with real fuel metering where intrinsics cost one
cycle; wasmer's metering middleware is not exposed by the Crystal shard.

**Size limits, and what CROBOTS did.** CROBOTS capped a robot at 1000
machine instructions (`CODESPACE`), 500 stack entries (`DATASPACE`),
8-character identifiers and 4 robots, and simply refused anything larger.
The equivalent here is the glyph budget: every pass re-emits the glyphs it
did not reduce, so the total emitted is the work done. A flat robot the
size of `sniper` emits about sixty thousand glyphs; two million is a few
hundred passes over a robot several times that size, and a long operator
chain or deeply nested parentheses hit it in well under a second instead
of running to the square of their length. Source is also capped at 20 KB
by the web app. The parser itself stays the same simple loop; the budget
is one comparison per pass.

**Animation approach.** Fossil serves our Markdown with a script-src policy
that only allows scripts carrying its nonce, and it passes raw HTML blocks
through. Three ways to animate under that: (1) SVG with SMIL `<animate>`
elements, no script at all, keyframes interpolated by the browser; (2) CSS
keyframe animations in an inline `<style>`; (3) a small script using the
`FOSSIL_NONCE` Fossil hands the CGI, which allows real player controls.
The page uses (1) now: it is the simplest, it is smooth, and the same
keyframe data can later feed (3) for play/pause/scrub without changing
the simulation. Pikchr stays for the static, printable frame and the
teaching view; it cannot animate.

Interpreter and WASM agree by construction on: floored division, division
by zero yielding 0 (as CROBOTS), logical `&&`/`||` evaluating both sides
and yielding 0/1, implicit function return being the last expression
statement executed with loops resetting it to 0. Strings are rejected by
the WASM emitter (`puts "text"`), which the examples never use.

Deliberate deviation from CROBOTS: the scanner normalizes both angles in
the wrap-around branch, so a scan at 359 sees a robot at 0 as the manual
promises (the original never normalized and could not).

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
- **`crystal_emitter.cr`, `riscv_emitter.cr`**: empty files. (`dot_emitter.cr`
  was a third placeholder here; phase 6 retires it for a markdown/pikchr
  emitter, so it is no longer part of the plan.)
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
   `crystal-robots -> <checkout>/bin/crystal-robots`, the same way Ollama-Codex's
   `/var/www/cgi-bin/ollama-codex` is a symlink to its `bin/`. A rebuild is
   the deploy; the CGI spawns fresh per request. URL: `/ext/crystal-robots/...`.
   The repo carries `fossil-skin/mainmenu` mirroring the deployed menu
   (Agents, Docs, Run) so the app is in the Fossil menu.
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
   they stay correct under `/ext/crystal-robots` and under
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

### Phase 5b: browser-hosted WASM compiler, ahead of the self-hosted server

MAINTAINER 2026-09-14: getting a static-hosted compiler built to Crystal's
`wasm32` target and running entirely in the browser is a higher priority
than our own self-hosted HTTP server, though the server stays in scope.

MAINTAINER 2026-09-19: hosting target fixed —
[jadonk.github.io/crystal-robots](https://jadonk.github.io/crystal-robots/),
published by `.github/workflows/pages.yml` on the GitHub mirror (trunk
reaches it through the Forgejo push mirror), Pages source "GitHub
Actions". The compile target is **`wasm32-unknown-wasi`**, not
`wasm32-unknown-unknown` as first drafted above: `wasm32-unknown-unknown`
has no libc at all in Crystal's stdlib, so nothing past a no-op `main`
builds; `wasm32-unknown-wasi` is the target the stdlib actually supports,
provided a wasm32-wasi libc/libgc/libpcre2. The static site lives in
`site/` (`index.html`, `app.js`, `wasi-shim.js` versioned; `crystal-robots.wasm`
generated by `scripts/ci.sh --with-wasm32` and gitignored, same as
`docs-api/` and `bin/`).

**Phase 5b-1 spike, answered (2026-09-19).** All three known unknowns
from the original item 1, plus one nobody had asked yet:

- **Build coverage: all of it.** Every file `src/compiler` requires —
  tokenizer, parser, checker, interpreter, WASM emitter, `Regex` and all —
  builds and links for `wasm32-unknown-wasi` unmodified. The link needs
  `-L <wasm32-wasi-libs>/lib/wasm32-wasi` on `crystal build`'s
  `--link-flags`; without it, `wasm-ld: error: unable to find library
  -lc`. The libs: [lbguilherme/wasm-libs](https://github.com/lbguilherme/wasm-libs)
  release **0.0.3** (its only release), `wasm32-wasi-sysroot.tar.gz`
  (headers plus `lib/wasm32-wasi/*.a`, including `libc.a`, `libgc.a`,
  `libpcre2-8.a`) — pulled in the same shape as `scripts/install_wasmer.sh`
  by `scripts/install_wasm32_wasi_libs.sh`, installed under
  `./.wasm32-wasi-libs` (`WASM32_WASI_LIBS`), wired into `scripts/ci.sh`
  as `--with-wasm32`.
- **The GC runs.** Boehm GC (`libgc.a` from the same libs) initializes
  and collects normally — confirmed by exercising the parser/checker on
  every example robot repeatedly in one instance, not just a smoke test.
- **Module size:** 1.7 MB in debug (`crystal build`'s default), 1.3 MB
  with `--no-debug`, **716 KB** with `--release --no-debug` (what
  `ci.sh --with-wasm32` and the Pages workflow ship). All three round-trip
  identically; `--release` only shrinks it.
- **The unasked fourth unknown, and the one that shaped the design:
  exceptions are stubbed out on this target.** Crystal 1.18.2's
  `raise` (`/usr/lib/crystal/core/raise.cr`, `{% if flag?(:wasm32) %}`)
  prints the exception to stderr, hits `LibIntrinsics.debugtrap` (a WASM
  `unreachable` instruction) and never reaches its own `LibC.exit(1)` —
  confirmed by testing, not just reading the source: a `rescue` sitting
  directly around the `raise`, one frame up, still never runs, because
  the trap fires before any unwinding machinery would. Every raise on
  this target — a parse error, `Interpreter::StepLimit`,
  `WASM_Emitter::Unsupported` — takes down the whole module instance, not
  just the call. `src/browser.cr`'s design follows from that: the JS
  shim treats a trap as an ordinary failed call (read what reached
  stderr, start a fresh instance next time) rather than something to
  catch inside the module, and `crd_run` (derivation, checker, WASM
  emit — none of which normally raise on a checked-clean program) and
  `crd_interpret` (which can hit the step limit on any `while true`
  fight loop, i.e. most real robots) are two separate exported calls so
  a trap in one cannot erase the other's already-computed report.

**The wasmer Crystal shard cannot drive a WASI module reliably.** Tried
first for `spec/wasm32_spec.cr`, matching the `wasmer_it`/`-Dwasmer`
pattern `spec/wasm_spec.cr` already uses: the shard's own `Wasmer::Wasi`
convenience layer segfaults inside `wasi_env_new` after a handful of
calls in one process, and its lower-level `Function`/`ImportObject` API
(the one `WASMSpec` in `spec_helper.cr` already drives reliably for
Phase 4's `env.*` imports) crashes wasmer 4.4.0 itself — `fatal runtime
error: Rust cannot catch foreign exceptions` — on any host import
function with zero results, which `proc_exit` (WASI's
`(param i32) -> ()`) must be; both reproduce in a few lines outside this
project's code. `spec/wasm32_spec.cr` does not depend on wasmer at all:
it shells to `node spec/support/wasm32_check.mjs`, which drives
`site/crystal-robots.wasm` through the real `site/wasi-shim.js` — the
same code the browser loads, so there is exactly one WASI implementation
in this repo, not a second one for CI to drift out of sync with. `node`
is required on `PATH` for `--with-wasm32` (present on the usual GitHub
Actions runners and this host); without the flag, or without
`site/crystal-robots.wasm` having been built, the wasm32 specs are
pending with their reason, same contract as the wasmer specs.

1. **Browser-hosted WASM compiler (priority), done.** Live and verified
   at [jadonk.github.io/crystal-robots](https://jadonk.github.io/crystal-robots/)
   (2026-09-19). `src/browser.cr` exports
   `crd_alloc`/`crd_run`/`crd_interpret` and their result accessors as
   plain top-level `fun`s — WASI's application ABI only requires a
   `_start` a host calls once, but nothing stops further calls into other
   exports afterward as long as the host does not treat a non-zero exit
   as fatal (`_start` only calls `proc_exit` then); the runtime init
   (GC, `Crystal.main`) that every Crystal program needs happens during
   that one `_start` call, same as it would for a CLI. `site/wasi-shim.js`
   is the hand-written host: only the 7 WASI imports the module actually
   uses (`wasmer inspect site/crystal-robots.wasm` lists them —
   `args_get`, `args_sizes_get`, `fd_fdstat_get`, `fd_fdstat_set_flags`,
   `fd_write`, `proc_exit`, `random_get`), no framework, no CDN;
   `site/app.js` is the page glue (textarea, Run button, rendering);
   `site/index.html` is the page. First concrete target, done: pasting
   `examples/test.cr` (`bin/crystal-robots -c`'s own smoke-test robot)
   round-trips through tokens/derivation, checker report, interpreter
   trace and emitted `.wasm` bytes byte-for-byte identical to the native
   CLI on the same source — the derivation string, the checker's (empty)
   problem list, the interpreter's step count and `puts` output, and the
   emitted module's bytes all match exactly; verified for every example
   robot's derivation and checker report, and specifically for `test.cr`'s
   full interpreter trace and WASM bytes (`spec/wasm32_spec.cr`).
   Battle in the page, deferred by this unit, is Phase 5b-2 (above): the
   same `Field`/interpreter engine, driven without fibers or `raise` so a
   battle can run more than one call's worth of work in the same module
   instance (`src/battle/step_robot.cr`), exported as `crd_battle_run`,
   drawn with the served page's own SVG renderer (`Battle.svg_animation`,
   `src/battle/svg_replay.cr`) rather than a second one in JavaScript.
2. **`-p PORT`.** Starts an `HTTP::Server` using the same router through the
   `Web::HTTP` adapter. Stays in scope, secondary to the browser-hosted
   compiler above.
3. **`-s DIR`.** Writes the page shell and static assets for plain file
   hosting. Stays in scope, secondary to the browser-hosted compiler above.

### Phase 6: teaching layers

MAINTAINER 2026-09-14: move away from the dot emitter; replace it with a
markdown/pikchr emitter that improves on the compilation visualization the
parse page already does for the passes, now applied to the AST tree-walk
side of the problem (the interpreter, not the tokenizer).

The "peel back a layer" goal: a **markdown/pikchr emitter** — the AST
tree-walk rendered as Pikchr diagrams inside Markdown, the same family as
the parse page's pass-by-pass derivation but for the interpreter's walk
instead of the tokenizer's passes. Each diagram shows the walk order (which
node is entered and left, in sequence), the active scope chain (locals,
globals, the current function's parameters), and the CROBOTS cycle charge
accumulated so far, the way the parse page already teaches the tokenizer's
passes. `crystal_emitter` (AST back to Crystal that compiles with the
prelude) and later `riscv_emitter` stay as listed. A language reference for
the subset and a port of the CROBOTS manual sections, published by the
existing `crystal docs` pages job.

The Tournament (`src/tournament/tournament.cr`, wired up at `/tournament`
in `src/web/cgi.cr`) is a teaching layer of a different kind: its design
was worked out live with the bash user, round by round, on the wiki page
"Tournament ideas", not decided up front. Pool size, best-of-3 only in the
bracket, the no-winner and points-tie refight rules, small-tournament
byes, and the later link-length and refight-budget fixes born from real
play are all recorded there in the order they were decided. That page,
not this plan, is the design record for any future change to the
tournament format.

### Phase 6 correction and expansion (2026-09-17)

MAINTAINER 2026-09-17: three corrections to the Phase 6 read above, plus
new backlog scope for the battlefield-visuals and editor goals. Two
standing invariants bound all of it, restated here because every item
below has to be checked against them: (1) a battle stays reproducible
without saving anything beyond what already reproduces it today — robot
source, seed and cycle count, the same trick the tournament's `mv=`
outcome string already applies at a coarser grain (previous section); no
feature here may require persisting full frame logs to replay a match.
(2) the compiler, interpreter and battlefield rules do not change for any
visualization or editor work; a diagram or an editor is a new *view* onto
the existing engine, never a second implementation of it.

1. **Three distinct views, not one.** "The AST tree-walk... rendered as
   Pikchr diagrams," above, reads as a single feature; it is really three,
   and only the third was previously written down:
   - **Parsing as it is done** — the parse page's existing pass-by-pass
     derivation (Phase 1, shipped). Unchanged.
   - **The AST once built** — a new, static structural diagram of the
     parsed tree, what `dot_emitter` was going to draw with Graphviz
     (`examples/test.dot`), now rendered as Pikchr/Markdown instead of
     `dot`, matching the drop-`dot` decision already made 2026-09-14.
     This is new work; nothing renders it today.
   - **The interpreter's walk** — the tree-walk trace (walk order, scope
     chain, cycle charge) already planned above. Execution, not
     structure; keep it a separate diagram from the AST-once-built view
     even though both are Pikchr-over-Markdown and both read the same
     AST.
   `examples/test.dot` and its `.svg.png` sample stay only as reference
   for the shape of a diagram, not as an output format to reproduce.
2. **`crystal_emitter` round-trips.** Compiling a crystal-robots source to
   its AST and back out through `crystal_emitter` must reproduce source
   that itself parses, checks and battles identically to the original —
   a golden per-example spec (source → AST → `crystal_emitter` →
   recompile → same checker result and same battle trace under a fixed
   seed), not just "the file exists." This bar carries forward unchanged
   once GPCR (next item) exists: whichever front end produced the AST,
   `crystal_emitter`'s round-trip guarantee must still hold.
3. **GPCR, forward-looking.** A future Crystal-language subset/library/
   annotation DSL that can be graphically rendered (name and scope as
   given by the maintainer; confirm with the coordinator whether it is
   the same codebase as the "GP-Crystal" reference deployment already
   cited in Phase 5, or a new one, before assuming either). crystal-robots
   keeps its own syntax; GPCR is additive, not a replacement. Aspirational
   direction, not scheduled: crystal-robots's grammar becomes a subset of
   GPCR's Crystal subset, so one parser/checker/interpreter/emitter
   pipeline serves both as interchangeable front ends on this same
   server — the strongest demonstration available here of what a shared
   compiler backend buys. Until that work starts, the only obligation on
   Phase 6 work is to not paint the AST/emitter interfaces into a
   crystal-robots-syntax-specific corner where the cost of a second front
   end would otherwise be avoidable.

New backlog scope opened by the same instruction, aimed at the stated
goal: get a young robot-builder like the bash wiki user from "interested"
to "able to ship a robot" with less friction.

4. **Battlefield visual upgrades**, built on the already-prioritized
   Phase 5b browser-hosted compiler: runtime-configurable cycle count and
   playback speed with no server round-trip; a dynamically selectable
   number of rendered cycles at a much higher rate than today's one
   SMIL-replay-per-page-load path; frames chosen so that recorded events
   (cannon fire, missile impact — the Phase 3 frame trace already carries
   them) are never skipped by a fixed-interval downsampling choice;
   optionally, a robot's wiki page carries a Pikchr fragment the renderer
   substitutes for the default glyph, for a custom look.
5. **Execution stepping**, source-level and WASM-level side by side —
   CROBOTS's own single-step debugger is the inspiration, kept usable
   from both the browser and the CLI (`-t`/`-i` already give a coarse
   form of this; extend rather than replace).
6. **A browser robot editor** that forks any example or saved wiki robot
   into an editable buffer, checks it live against Phase 5b's
   browser-hosted checker instead of round-tripping to the server, and
   shows one consolidated cheat-sheet next to the editor rather than the
   full `crystal docs` API dump — evolving `src/web/robot_api.cr`'s
   existing kid-worded, grouped panel (Sense/Move/Shoot/Math/Output) in
   place rather than building a second reference surface.

A new wiki page, ["Robot Builder ideas"](/wiki?name=Robot+Builder+ideas),
opens the same live-design loop with the bash user for items 4-6 that
"Tournament ideas" ran for the tournament: ask concrete either/or
questions with a Pikchr sketch, build exactly what comes back. Wait for
answers there before committing to specifics beyond what is written
above.

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
- `/docs/` was dropped from `.gitignore` so the git mirror carries
  `docs/*.md`. `crystal docs` (the API reference from the doc comments)
  still goes to `public/`, which stays ignored. How the API docs get built
  and surfaced is to be worked out with the Ollama-Codex project, which
  has a `build-docs` step that embeds `crystal docs` output into its
  binary and serves it at `/ext/docs`; the same shape would fit here.
- Preview builds: `agent-tool session-preview` needs the session binding
  from the primary repository, so it runs on the host (Thread UI button or
  the coordinator), not from inside the sandboxed session checkout.

## 4. Parser architecture: decided

2026-09-10: option A, the progressive multipass tokenizer using reserved
UTF-8 glyphs and the existing regex grammar table. The unresolved logic is
now written down in `docs/PARSER.md` and demonstrated by
`scripts/multipass_prototype.cr`. The alternative that was offered (a
hand-written recursive-descent parser, of which a "Pratt parser" is the
operator-precedence variant) is dropped.

## 5. Immediate next steps

1. Spike: a wasmer-backed `Battle::Robot` whose `env.tick` blocks on the
   scheduler channel; if the runtime tolerates it, WASM robots join the
   field with the same protocol as interpreted ones.
2. Phase 7 leftovers: the recurring `ci.sh --with-wasmer` regression task
   (coordinator sequences it); dropping `.gitlab-ci.yml` once the GitLab
   mirror is retired; the docs pages inside the Fossil chrome if the raw
   passthrough proves awkward.
3. Live-editing loop for wiki robots: the battle result already links to
   the page editor; a "battle again" link from the wiki editor back is the
   missing half.

## 7. Coordinator answers for Phase 7 (2026-09-11)

Answered by the Ollama-Codex coordinator; items marked MAINTAINER are the
maintainer's decisions. Recorded here verbatim in substance.

1. **API docs.** Same shape as Ollama-Codex, own binary: a `build-docs`
   subcommand of `bin/crystal-robots` runs `crystal docs` into an
   ignore-globbed directory; a compile-time macro embeds every file under
   it; served at `/ext/crystal-robots/docs`, never at ocx's `/ext/docs`.
   Artifact lives in the checkout, unversioned. `build-docs` runs before
   `shards build` or the binary ships empty docs.
2. **Deploy.** Not automated; the served symlink points at
   `<primary>/bin/crystal-robots` and trunk-ops rebuilds by hand after each
   merge (now on its checklist for served peers; a daemon-side deploy is
   ticketed). The preview dispatcher builds the first target in
   `shard.yml`, which is `bin/crystal-robots`. Corrected 2026-09-11: the
   served binary is newer than trunk (1e1fdc07); the gap is simply this
   branch waiting for its merge through the gate. Session work is reported
   as branch, commit and suite result in the thread; the coordinator
   routes it to trunk-ops (isolated-clone verification, suite, maintainer
   word, merge, rebuild).
3. **CI.** No Fossil hook or cron; the gate is the task pipeline (agent
   runs the suite, validator checks, trunk-ops re-runs on a merge
   stand-in). `scripts/ci.sh` is the one command all of them call: shards
   install, build-docs, shards build, spec, format check, example builds,
   non-zero on any failure. MAINTAINER: sessions install wasmer 4.4.0 only
   when the work touches WASM; `ci.sh --with-wasmer` installs it under the
   checkout if absent and runs the differential specs; plain `ci.sh`
   reports those specs as pending with the reason. A recurring regression
   task runs `ci.sh --with-wasmer` on trunk about weekly.
4. **Permissions.** Ollama-Codex tiers, not "any named login": identity is
   `FOSSIL_USER`, permission is `FOSSIL_CAPABILITIES`, code maps routes to
   capability letters and the repository's grants decide who holds them.
   Overview and examples on `o`/`h`; battle and anything that saves on `i`.
   MAINTAINER: parse also stays on `i` until the compiler and battlefield
   run client-side in WASM, at which point parse opens for free.
5. **User data.** Wiki pages `robot/<name>` are right: a saved robot is
   project content, versioned, diffable and editable under `j`. The
   convention for peers is an `<app>/<name>` page prefix.
6. **Menu.** Keep `fossil-skin/mainmenu` as the source of truth; an
   Ollama-Codex ticket makes a served repo's versioned menu lines required
   entries of its onboarding invariant. The Run entry was pasted by hand.
7. **Ignore and mirror.** Versioned `.fossil-settings/ignore-glob` is the
   convention (`bin/`, `lib/`, `public/`, the docs artifact), with
   `.gitignore` kept as its mirror. MAINTAINER: mirroring standardizes on
   Forgejo pulling from this server over https and pushing onward to
   GitHub/GitLab; no secrets on this host. Keep `.gitlab-ci.yml` only while
   the GitLab mirror exists; README links move to the Fossil repository.
8. **Previews.** Host-side stays sanctioned (Thread UI button or the
   coordinator); a `preview` verb over the daemon loopback IPC is the
   planned paving for sandboxed sessions.
9. **robot-restrict.** Leave unset; battle needs a login already, and any
   robot-facing setting gets a real-browser check first.
10. **Live output.** The port 8443 daemon is already per-project with its
    own secret; a battle stream would be a new channel kind fed by a file
    the CGI writes. The one-shot SMIL SVG stays the first cut.

MAINTAINER standing ask: a human must experience key user-visible changes
before long, prompted by a short "try this" list. Status rows above that
are user-visible carry the tag **[try]** until the maintainer has actually
tried them, at which point the row is retagged **[tried DATE]**. 2026-09-14:
the maintainer confirmed phases 1, 2, 3 and 5 have all been tried; their
rows above are retagged accordingly. Phase 4 and 6 rows with open
`[try]` tags stay open. Section 8 keeps the current short list.

## 8. Try this (user-visible changes to experience)

1. Overview at `/ext/crystal-robots/`: saved robots table with
   descriptions and fight links; log in to see the battle link and parse
   form.
2. Battle picker: check hunter, circler and counter, run one match, watch
   the replay at the default pace, then set Matches to 5 for a score table
   and open one replay link.
3. A wiki robot's view page (`/ext/crystal-robots/wiki/hunter`): source,
   derivation, checks, fight and edit links.
4. Parse form: paste a robot with a typo and read the located problem.
5. Tournament (`/ext/crystal-robots/tournament`): check three or more
   robots (or **Check everyone**), press **Start tournament**, then
   **Start round 1**, then keep clicking **Run next round →** until the
   trophy page names a champion; open a fight's replay link along the way.
