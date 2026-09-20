# The tutorial: commit-by-commit, phase by phase

This is the as-built index the [chasm-style blog
series](https://blog.scottlogic.com/2019/05/17/webassembly-compiler.html)
links against. `docs/PLAN.md` is the design plan written before this
history existed; this file is the record of what actually landed, in the
order it landed, once the whole arc reached parity with trunk. Every
commit below compiles, passes `crystal spec`, and is demonstrated by a
spec example or a `crystal run`/`bin/crystal-robots` invocation named in
its own check-in comment — that was the rule for every commit from the
first to the last, and it still holds: re-checked commit by commit against
this exact list before this file was written (see "Verification" below).

This history is a **parallel line, not a replacement**: the maintainer's
decision on ticket 7b6bf1909f (2026-09-20) keeps trunk exactly as it is.
This branch is the tutorial line on its own, cited by hash the way
chasm's own commit list is cited from its blog post.

**Branch name proposed for the blog to cite:** `tutorial` — a stable,
short name distinct from this session's own long branch identifier, for
trunk-ops to tag once this file lands. Until that tag exists, cite the
session branch, `session/bab6654802593d134c4c380d63e96c01a10e052943f93399d6829382eb005b93`,
or the individual check-in hashes below directly (a hash never changes,
tag or no tag).

## How to follow along

Each row below is one check-in. Clone or open this repository, then for
any commit in the list:

```
fossil update <hash>
crystal spec              # every commit's own suite, green
crystal run src/cli.cr -- --version   # or whatever -t/-c/-i/-m example
                                        # that commit's message names
```

`crystal spec -Dwasmer` additionally exercises the real WebAssembly path
under wasmer 4.4.0 (pinned); plain `crystal spec` reports those examples
pending on a machine without libwasmer, rather than failing. From Phase W
onward, `crystal run ci.cr -- --with-wasmer --with-wasm32` is the one
command that builds, tests and smoke-tests everything, wasmer and the
browser build included.

## Verification

Every commit hash below was checked out in a scratch checkout (separate
from this session's own working tree, which never leaves this branch) and
rebuilt from scratch: `crystal build --no-codegen src/cli.cr` for a clean
type-check, then `crystal spec` (the default, non-wasmer suite) for a real
pass. All fifty-three still build and still pass, unchanged, today.
`crystal spec` at the tip itself: 239 examples, 0 failures, 46 pending
(41 wasmer-gated, 4 wasm32-gated, 1 docs-embedding placeholder — the same
three gated groups every phase report already named).

## Commit list

### Phase A — the compiler and WASM emitter (mirrors the chasm blog post)

1. `9afb3be606` **A.1 project skeleton** — a version-only CLI; `crystal spec` and `crystal run src/cli.cr -- --version` both work.
2. `893d224abc` **A.2 the minimal WASM module** — the 8-byte magic header and version, nothing else; spec runs it through wasmer.
3. `1f21f606bc` **A.3 a hand-assembled add function** — one exported function, opcodes written by hand, no compiler yet; `add(1, 2) == 3` under wasmer.
4. `ea4f41b331` **A.4 the multipass tokenizer and a real compiler for `puts NUMBER`** — first AST-driven emitter; `-t` prints the derivation.
5. `5d155c1f10` **A.5 binary expressions** — `+ - * / // %`, parens, unary minus, precedence and associativity.
6. `292637363a` **A.6 global variables and assignment** — `global(name, init)`, `=`.
7. `208da8aec3` **A.7 comparisons and while/until loops** — `== != < > <= >=`, `while`/`until`/`break`.
8. `5fdf12ab84` **A.8 if / elsif / else** — a fizzbuzz-style spec mixes it with while.
9. `fa09ddcb31` **A.9 the CROBOTS builtins as host imports** — 0/1/2-arg builtins become typed `env.*` imports.
10. `7d65187bd6` **A.10 user-defined functions** — `def`, calls with arguments, implicit/explicit return, recursion (`fact(5) == 120`); a real grammar ambiguity found and fixed.
11. `95b7f5d665` **A.11 `main("Name") do...end`** — the entry point; ordering spec proves before/main/after execute in source order.
12. `0ac94d459b` **A.12 the checker** — undefined names, call arity, misplaced return/break, duplicate def, all with source locations.
13. `bd2a972b62` **A.13 the reference interpreter** — a tree-walking evaluator behind `Host`; the first differential spec (interpreter vs. wasmer) agrees.
14. `8259d9793a` **A.14 CLI wiring and a disassembler** — `-t -k -c -i -d`; `-c`'s module passes `wasmer validate`.
15. `def02e4316` **A.doc** — docs/PLAN.md marks Phase A done.

### Phase B — grammar and checker parity with the shipped example robots

1. `c9430f2c77` **B.1 comments and true/false literals** — `#` lexes away like whitespace; `while true` means what it looks like.
2. `4702129598` **B.2 parenthesized builtin calls** — `scan(angle, res)` alongside the bare form; documents the `puts (1) + 2` ambiguity on purpose rather than silently "fixing" it.
3. `e3bb217383` **B.3 implicit global constants and bare zero-arg calls** — `C1X = 10` at top level; bare `run`/`change`/`new_corner`.
4. `9827d0054d` **B.4 compound assignment** — `+= -= *= %=`.
5. `2779b876e8` **B.5 logical and/or and bitwise xor** — no short-circuiting, matching docs/PLAN.md; also documents and works around an intermittent wasmer-crystal GC finalizer crash (`GC_DONT_GC=1`).
6. `a9703a956b` **B.6 assignment inside a condition, bare call as a call argument** — `while ((range = scan(angle, res)) > 0)`; fixes a checker gap on names first assigned inside a condition.
7. `c2b46eecd4` **B.7 case / when / else** — the last statement shape in the grammar.
8. `aca2453f53` **B.8 the six example robots parse — grammar parity reached** — counter/rabbit/rook/sniper/target parse, check clean and compile on the first try; closes the parser+checker half of the coordinator's ordering.

### Phase C — the battlefield: physics, missiles, the scanner, real matches

1. `4f20a84a8c` **C.1 cycle charging** — `Interpreter::Costs` mirrors CROBOTS's per-instruction costs; a differential spec confirms the interpreter and `env.tick`-instrumented WASM charge identical totals.
2. `c3d286f75f` **C.2 robot motion physics** — `Battle::Field`, ported from CROBOTS's `motion.c`/`main.c`: acceleration, the turn-speed cutoff, wall/robot collision.
3. `d051dc638d` **C.3 missiles** — firing, flight, explosion-radius damage, ported from `intrins.c`/`motion.c`; a real quirk (a negative-range cannon call "succeeds" without firing) preserved on purpose.
4. `5b632885d3` **C.4 the scanner and a real Host** — `Field#scan`, `RobotHost`; a real robot's source runs through the interpreter and moves the field's own robot.
5. `d70d3ea832` **C.5 interleaving robots into real matches** — `Battle::Match`; a raw `Fiber`/`resume`/`yield` loop does not pause the way it looks like it should on this runtime, replaced with a `Channel` round-trip — confirmed by a minimal repro before trusting it.
6. `dbca0f8529` **C.6 CLI wiring for matches, and a real crash-safety fix** — `-m -l --seed`; a robot's runtime crash used to hang the match scheduler forever, fixed and pinned by a spec.

### Phase D — the Fossil + CGI web layer

1. `c67c57da55` **D.1 the CGI entry point, capability gate, and overview** — dispatches on `GATEWAY_INTERFACE`; `Capabilities` gates every route the way GP-Crystal/Ollama-Codex already do.
2. `ac2e9f535e` **D.2 the example page** — a shipped example's source and derivation; `Markdown.fence` defeats fence-injection from untrusted content.
3. `3364938838` **D.3 the parse page, and the parser's own work budget** — paste-a-robot; `Parser.max_passes`/`max_glyphs` cap unbounded work on pathological input, the parser's first exposure to untrusted text.
4. `9b76236604` **D.4 the battle page** — check 2-4 robots, run one seeded match, see a Pikchr frame; its own smaller cycle limit than the CLI's.
5. `eb19e759a7` **D.5 saved robots as wiki pages** — reads `robot/NAME` wiki pages through the `fossil` CLI itself; verified against this repo's own real `hunter`/`circler`/`dodger`/`turret`/`wallhugger` pages.
6. `df320bec0b` **D.6 the fossil-skin menu** — `fossil-skin/mainmenu`, confirmed byte-identical to trunk's deployed skin; closes the CGI web layer list.

### Phase T — the tournament

1. `02a0c2041e` **T.1 pool play** — pools, round-robin scoring, refight-then-0-0, tie-break by recursive mini round-robin, built word-for-word from the wiki page "Tournament ideas".
2. `1d8f821ac0` **T.2 the bracket** — seeded byes, best-of-3, a shared per-match refight budget (a real bug the wiki page itself records, fixed here the same way).
3. `dc2b57d5e7` **T.3 the tournament web layer** — a designer form and link-driven bracket pages; all state carried in a compact `mv=` moves string so replaying a decided fight costs no cycles.
4. `35260c5e91` **T.4 refuse a tampered tournament link** — a real finding: a hand-edited `mv=` could crown a fake champion; every bracket fight is now re-verified before showing a champion.
5. `5726e3d177` **T.5 link the tournament from the overview** — closes a discoverability gap; completes the tournament slice.

### Phase U — the remaining real trunk features

1. `492fcf474b` **U.1 version reports the check-in it was built from** — `manifest.uuid` at compile time; `/version` route.
2. `39415ae8eb` **U.2 crystal and riscv emitter placeholders** — byte-for-byte empty, matching trunk's own reserved-but-unimplemented files.
3. `339f83ba03` **U.3 versioned `robots/*.md` and the publish script** — five saved robots' prose+source versioned in the tree; `scripts/publish_wiki_robots.sh` verified against a throwaway repository.
4. `dd6f4cb4ea` **U.4 the robot API reference panel** — spec-pinned against `Interpreter::BUILTIN_NAMES` so a builtin can never go undocumented or made-up.
5. `3461ff170a` **U.5 the API docs route and build-docs** — `crystal docs` output embedded and served through Fossil's chrome; verified with docs-api both absent and built.
6. `ad02b3543e` **U.6 `scripts/ci.sh` as the one CI command** — verified twice for real, with and without wasmer, from a fully clean tree.

### Phase W — the browser-hosted static WASM compiler and its Pages hosting

1. `79b81945bf` **W.0 port `compiler.cr`'s behavior** — `Compiler.interpret`/`.compile_to_wasm`, the two convenience wrappers the browser build needs.
2. `8321d270aa` **W.1 the wasm32 spike** — `src/browser.cr` built for `wasm32-unknown-wasi`; the no-exceptions finding (a `rescue` around a `raise` in the same function still traps) confirmed twice by testing the real module, not the source.
3. `24da0e6943` **W.2 the static page and WASI shim** — `site/wasi-shim.js` (7 WASI imports, no framework), `site/index.html`, `site/app.js`; verified end to end through a small Node driver.
4. `175b9029c9` **W.3 the wasm32 spec and the ci.sh flag** — `spec/wasm32_spec.cr` drives the real shim through node; `--with-wasm32` installs the wasm32-wasi-libs sysroot.
5. `4b179e1971` **W.4 the GitHub Pages deploy workflow** — `.github/workflows/pages.yml`, byte-for-byte trunk's own, triggering on `main`/`dev`.
6. `38321a2764` **W.5 pin the Pages workflow with Crystal's own YAML** — corrects an earlier wrong claim ("no YAML library available"); `YAML.parse` pins the trigger and step order; documents the `on:` → `true` YAML 1.1 gotcha.
7. `60538ebc82` **W.6 `ci.cr` replaces `ci.sh`, per maintainer direction** — a direct Crystal port, `scripts/ci.sh` deleted outright; a real `WASMER_DIR`-export bug found and fixed while verifying it.

## Blog post outline per phase

Each phase below is sized as one post, mirroring the shape of the single
chasm post but split at the seams this history's own coordinator used to
review it — motivation and design first, then a walk through that
phase's commits in order, then a live demo.

**Phase A — "Building a WASM compiler for CROBOTS, chasm-style"**
- Why chasm's approach (one feature per commit, always green) suits a
  compiler tutorial; why this project swaps chasm's hand-written
  recursive-descent parser for a *progressive multipass* regex grammar
  (link `docs/PARSER.md`), and what that trade buys a reader (`derivation`
  prints the whole parse as one line per pass — show it).
- Walk A.1 → A.14 in order: minimal module → hand-assembled `add` →
  first AST-driven compiler → expressions → globals → loops → branches →
  builtins as host imports → functions (with the real ambiguity bug as a
  sidebar) → `main` → the checker → the reference interpreter → the CLI.
- Demo: compile and run `examples/hello.cr` three ways (`-t`, `-c` under
  wasmer, `-i`), then `-d` to show the disassembly.

**Phase B — "Getting the grammar to parity with real robots"**
- Why grammar-first, example-robot-second: writing a spec-driven grammar
  against real `counter.cr`/`rabbit.cr`/`rook.cr`/`sniper.cr`/`target.cr`
  instead of inventing test programs, and what gaps that surfaced.
- Walk B.1 → B.8: comments/booleans, parenthesized calls (and the
  documented ambiguity), implicit globals and bare calls, compound
  assignment, logical operators (with the wasmer GC crash sidebar),
  assignment-in-condition, case/when, and the B.8 payoff — five real
  robots parsing, checking and compiling clean on the first try.
- Demo: `bin/crystal-robots -k examples/sniper.cr`, clean; `-c` produces a
  module `wasmer validate` accepts.

**Phase C — "A real battlefield: physics, missiles, and cooperative robots"**
- Porting fidelity: why this phase reads CROBOTS's own C source
  (`motion.c`, `intrins.c`, `main.c`) fresh rather than working from
  memory, and what that discipline caught (the negative-range cannon
  quirk).
- Walk C.1 → C.6: cycle charging and the interpreter/WASM differential
  check, motion physics, missiles, the scanner and `RobotHost`,
  interleaving matches (the Fiber-vs-Channel finding as its own section —
  a good "debugging Crystal concurrency" sidebar), and the crash-hang fix.
- Demo: `bin/crystal-robots -m 3 examples/sniper.cr examples/rabbit.cr
  --seed 1`, showing a real scored match.

**Phase D — "Serving it from Fossil: a CGI robot lab"**
- Why CGI-over-Fossil rather than a standalone server: capability-based
  auth for free, no separate deploy.
- Walk D.1 → D.6: the entry point and capability gate, the example and
  parse pages (untrusted-input hardening as its own beat — fence
  injection, parser work budgets), the battle page and its Pikchr frame,
  wiki-page-backed saved robots, the shared menu skin.
- Demo: a screenshot or terminal capture of `/ext/crystal-robots`, a
  paste-and-parse round trip, and a battle between an example and a saved
  wiki robot.

**Phase T — "A tournament, built from a wiki page's own design notes"**
- The unusual source material: this feature was speced entirely from a
  wiki page of design Q&A ("Tournament ideas"), not from a spec document
  — worth showing a snippet of that page next to the commit that
  implements it.
- Walk T.1 → T.5: pool play, the seeded bracket (with the refight-budget
  bug the wiki page itself records), the link-driven stateless web layer
  and its `mv=` trick, the tampered-link finding as a security aside, and
  the overview link.
- Demo: play a real three-robot tournament through pools to a champion
  page, then flip one letter in the URL and show the "this link was
  changed" refusal.

**Phase U — "Catching up the rest: docs, versions, and one CI command"**
- Framing: this phase is deliberately unglamorous — closing every
  remaining gap the parity reports found, one commit per gap, same rule
  as always.
- Walk U.1 → U.6: version/manifest.uuid, the emitter placeholders (a note
  on why some files exist reserved-but-empty), versioned robot pages and
  the publish script, the spec-pinned API reference panel, embedded
  `crystal docs`, and `ci.sh` as the one gate command.
- Demo: a clean-tree `ci.sh`/`ci.cr` run start to finish, ending in its
  own "all green" line.

**Phase W — "Compiling to WebAssembly for the browser, and shipping it"**
- The punchline of the whole series: the same compiler this history
  built up statement by statement, now running with no server at all.
- Walk W.0 → W.6: the compiler.cr behavior port, the wasm32 spike (the
  no-exceptions finding is the centerpiece — show the failed rescue,
  then the working design), the static page and hand-written WASI shim,
  the spec that drives it through Node, the GitHub Pages workflow, the
  YAML-pinning correction (a small honest "I was wrong, here's the fix"
  beat), and `ci.cr` replacing `ci.sh` as the very last commit.
- Demo: open the deployed Pages site, paste a robot, click Run, and read
  the derivation/checker/interpreter-trace/WASM-hex report entirely
  client-side.
