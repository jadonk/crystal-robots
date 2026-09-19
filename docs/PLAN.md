# The tutorial history: a table of contents

This project's check-in history is written to be read, commit by commit, the
way [chasm's history](https://github.com/ColinEberhardt/chasm/commits/master/)
is read alongside [its blog post](https://blog.scottlogic.com/2019/05/17/webassembly-compiler.html).
Every commit listed below compiles, passes `crystal spec`, and is demonstrated
by a spec example or a `crystal run`/`bin/crystal-robots` invocation named in
its check-in comment. Where chasm hand-writes a tokenizer and a recursive
descent parser, this project uses the **progressive multipass tokenizer**
described in [docs/PARSER.md](PARSER.md): every pass rewrites a string of
reserved Unicode glyphs with a regex grammar rule, so `Program#derivation`
prints the whole parse as one line per pass. That design document is written
first, as the target; the commits below build up to it one rule at a time.

## Phase A — the compiler and WASM emitter (mirrors the chasm blog post)

1. **Project skeleton** — `shard.yml`, a `crystal-robots` CLI that only
   prints its version, `spec/spec_helper.cr`. `crystal spec` and
   `crystal run src/cli.cr -- --version` both work.
2. **Emit the minimal WASM module** — the 8-byte magic header and version,
   nothing else. Spec runs it through wasmer and checks it instantiates.
3. **A hardcoded `add` function** — one exported function, opcodes written
   by hand, no compiler yet. Spec calls `add(1, 2)` through wasmer and
   checks `3`.
4. **Tokenizer pass 0 and the first grammar rule** — lex integers and
   `puts` into glyphs (`Type`, `Program` from `docs/PARSER.md`); one rule
   reduces `puts NUMBER` to the program glyph. First WASM emitter driven by
   an AST instead of hand-written bytes. `bin/crystal-robots -t` prints the
   one-line derivation.
5. **Binary expressions** — `+ - * / // %`, parentheses, unary minus; the
   precedence/associativity guards from `docs/PARSER.md` section 2.
6. **Global variables and assignment** — `global(name, init)`, `=`.
7. **Comparisons and loops** — `== != < > <= >=`, `while`/`until`/`break`.
8. **`if` / `elsif` / `else`.**
9. **Builtin calls as host imports** — 0/1/2-argument builtins
   (`damage`, `puts`, `scan`, ...) become `env.*` imports, the CROBOTS
   sensor/actuator shape.
10. **User-defined functions** — `def`, calls with arguments, implicit
    last-expression return and explicit `return`.
11. **`main("Name") do ... end`** — the program's entry point, wrapping the
    rest the way chasm's default-main-proc transformer does.
12. **The checker** — a semantic pass: undefined names, call arity,
    misplaced `return`/`break`, duplicate `def`, with source locations.
13. **The reference interpreter** — a tree-walking evaluator behind a
    `Host` interface; a differential spec runs the same robot through the
    interpreter and through wasmer and compares output.
14. **CLI wiring** — `-t` (trace), `-c -o` (compile), `-i` (interpret), a
    `.wat` text emitter as a debugging aid.

## Phase B — the battlefield and the cycle model

1. CROBOTS physics ported from `motion.c`/`intrins.c`/`main.c` as
   `Battle::Field`; robots interleave one interpreter step at a time in
   fibers.
2. Seeded RNG, `-m MATCHES -l CYCLES --seed N` from the CLI.
3. CROBOTS-style cycle charging in the interpreter and matching
   `env.tick` calls in the WASM emitter; a differential spec checks both
   engines charge the same total.

## Phase C — Fossil + CGI hosting (the primary deployment)

1. One binary, dispatching on `GATEWAY_INTERFACE`; overview and example
   pages under a capability gate.
2. Parse page: paste a robot, see its derivation and checker errors.
3. Battle page: one seeded match rendered as a Pikchr frame, then an
   SMIL-animated replay.
4. Saved robots as wiki pages (`robot/<name>`); a publish script for the
   shipped examples.
5. The tournament bracket.
6. `build-docs`: `crystal docs` embedded and served in the Fossil chrome.

## Phase D — hardening and housekeeping

Request and parser budgets, input size caps, `scripts/ci.sh` as the one
gate command, wasmer pinned to a musl-compatible release,
`.fossil-settings/ignore-glob` mirrored to `.gitignore`.

## Phase E — the browser-hosted static compiler (upcoming)

1. Compile `src/compiler` (tokenizer, checker, interpreter) to
   `wasm32-unknown-unknown`.
2. A static page that loads that module and runs the parse/check/interpret
   passes entirely client-side — no server round trip.
3. Static hosting output published to the GitHub/GitLab Pages mirrors
   (`jkridner.beagleboard.io/crystal-robots`, `jadonk.github.io/crystal-robots`).

Phases B through E are the current level of functionality and the next
step beyond it; they are queued for continued work on this same history,
each phase's commits following the same rule as Phase A: compiles, specs
green, one feature per commit.
