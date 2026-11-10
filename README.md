# crystal-robots

crystal-robots is a programming game. You write a small program that drives
a robot, and it battles other people's robots on a square battlefield. You
can [play it in your browser](https://jadonk.github.io/crystal-robots/) now.

## What it's for

The game is the way in. You write robots in
[Crystal](https://crystal-lang.org), a programming language whose syntax is
simple to read, much like Ruby's. Then you follow that same code all the way
down: from the text you typed, through each step a *compiler* takes (the
program that turns code a person writes into instructions a machine runs),
to the instructions themselves. That path, from learning a language to
understanding its compiler, is the point.

The compiler here is kept small enough to read in an afternoon. Its ideas
still apply to much larger compilers, so what you learn carries over to
them.

Jason Kridner started crystal-robots for a personal reason too: to depend
on programming tools that can be read and changed all the way through,
down to the language itself, rather than on tools that can only be used as
given.

## What it's made of

- **Crystal**, for everything: the compiler, the battlefield, the web app
  and the robots. A robot uses a small part of Crystal: whole numbers,
  variables, `if`, `while`, functions, and the robot's *builtins* (commands
  the game provides, such as `scan`, `drive` and `cannon`).
- **CROBOTS**, the [1985 game by Tom Poindexter](http://tpoindex.github.io/crobots/)
  that crystal-robots follows. Its battlefield, its builtins and its *cycle*
  costs (how much time each operation takes) are ported from its C source.
- **WebAssembly**, a standard set of machine-like instructions that every
  web browser can run. The compiler's output is WebAssembly. The part that
  writes those instructions out as bytes comes from
  [chasm](https://github.com/ColinEberhardt/chasm), a small teaching
  compiler by Colin Eberhardt.
- **Fossil**, the version-control system that holds this project. Each
  saved version is a *check-in*, named by a short hash such as
  `66bc8fd2b2`. Fossil also serves the repository's web pages, including a
  *wiki* (pages anyone with permission can edit), and the game runs as one
  of those pages.

## How it's shaped

A robot passes through two stages inside crystal-robots. The *front end*
reads the code and works out what it means. A *back end* then runs it.

- **The front end.** A *parser* works out the structure of the code. This
  one works in *passes*, going over the whole text once per pass. Each pass
  applies exactly one *grammar rule*, a pattern such as "a number, a plus
  sign and a number make a sum". So every step can be shown:
  `bin/crystal-robots -t examples/counter.cr` prints one line per pass,
  showing the whole robot rewritten as symbols after that pass. A *checker*
  then reports mistakes, such
  as a name that was never defined, with their line numbers.
- **Two back ends.** The *interpreter* runs a robot directly from its
  parsed structure. The compiler instead turns it into WebAssembly. Both
  charge the same CROBOTS cycles, so a robot behaves the same either way.
- **One battlefield.** One simulation, ported from CROBOTS, runs every
  match, whichever back end runs the robots. Each match is *seeded*: the
  same robots and the same seed always give the same fight, so a result
  can be replayed and shared.
- **A check from outside.** Every robot is also a valid Crystal program.
  Crystal's own, full-sized compiler builds each example robot into
  *native* machine code, the instructions of the computer at hand.
  For that build, `src/prelude.cr` supplies the builtins as ordinary
  Crystal code. This is not a
  third way to play; it shows that a robot really is Crystal.

The same code serves three places to play:

- a web browser, where the compiler itself is compiled to WebAssembly and
  runs in the page with no server;
- a Fossil server, as the repository's own web app;
- the command line, with `bin/crystal-robots`.

## What success looks like

The [Status](https://ollama.openbeagle.org/crystal-robots/wiki?name=Status)
page says where the work stands today.

1. **Play in a browser.** A new player writes a robot, sees it checked, and
   watches it fight, with nothing to install. *Done:*
   [the public site](https://jadonk.github.io/crystal-robots/), with a
   [manual](https://jadonk.github.io/crystal-robots/manual/) and guided
   [challenges](https://jadonk.github.io/crystal-robots/challenge/).
2. **Play on the project's own server.** The game runs as the repository's
   web app. Saved robots live in its wiki, and a *tournament* (many robots
   playing round after round down to one champion) can be shared by its
   link. *Done:*
   [the app page](https://ollama.openbeagle.org/crystal-robots/ext/ocx2-cgi/app/crystal-robots),
   serving [check-in 66bc8fd2b2](https://ollama.openbeagle.org/crystal-robots/info/66bc8fd2b2).
3. **See how the code is read.** A player can watch the parser's passes
   and see the WebAssembly their robot became. *Done:* the site's
   [workbench](https://jadonk.github.io/crystal-robots/workbench/) page
   shows the passes, and its [front page](https://jadonk.github.io/crystal-robots/)
   shows the WebAssembly.
4. **Follow how it was built.** A tutorial rebuilds the project one change at a
   time, each with its code. *Done:* the
   [project blog](https://jadonk.github.io/crystal-robots/blog/), merged in
   [check-in 048d0ace53](https://ollama.openbeagle.org/crystal-robots/info/048d0ace53).
5. **Down to a real processor.** The compiler also emits instructions for
   RISC-V, a real processor design used in many small chips, and draws a
   robot's parsed structure as a diagram (with Graphviz's *dot* format). *Not yet:*
   `src/compiler/riscv_emitter.cr` and `src/compiler/dot_emitter.cr` are
   empty placeholders.

## The virtues behind it

crystal-robots is one of several projects built with
[OCX](https://ollama.openbeagle.org/ollama), a shared set of tools with
which people and AI agents build and run these projects together. Like
each of them, it follows OCX's four virtues:

- **Clearly stated:** anyone can tell what each part does. The parser
  applies one rule per pass and shows each pass, so a reader can watch it
  work.
- **Loosely coupled:** each part can be swapped without breaking the rest.
  The interpreter and the WebAssembly back end sit behind the same
  battlefield, and the browser, the server and the command line share the
  same compiler.
- **Demonstrably verified:** every claim is shown working, not just stated.
  `crystal run ci.cr` runs the whole test suite and builds every example
  robot natively. Run with `--with-wasmer` (wasmer is a program that runs
  WebAssembly outside a browser), it also checks that each compiled robot
  matches the interpreter, cycle for cycle.
- **Parsimoniously bounded:** it does no more than it needs to. The robot
  language has only what a robot needs, and the game keeps CROBOTS's rules
  rather than inventing new ones.

## Installation

```
shards build            # produces bin/crystal-robots
bin/crystal-robots -h
```

Crystal 1.14 or newer. Running the emitted WebAssembly (the specs and,
later, battles) needs the wasmer runtime; see Development below.

## Usage

`bin/crystal-robots` is one binary with several faces:

```
bin/crystal-robots -t examples/counter.cr           # print the parser derivation, one line per pass
bin/crystal-robots -i -l 5000 examples/counter.cr   # run robots in the interpreter, 5000 steps each
bin/crystal-robots -m 3 -l 100000 --seed 7 examples/counter.cr examples/rabbit.cr   # three seeded matches
bin/crystal-robots -c examples/sniper.cr -o sniper.wasm # compile a robot to WebAssembly (imports env.scan, env.cannon, ...)
bin/crystal-robots -c examples/sniper.cr --ticks -o sniper.wasm # also import env.tick(n) and charge CROBOTS cycles
GATEWAY_INTERFACE=CGI/1.1 bin/crystal-robots        # serve the web app (Fossil does this for you)
```

The easiest way to play is the [public site](https://jadonk.github.io/crystal-robots/). The compiler is built into the web page. You can provide sources for the various robots and watch them battle it out.

There are a lot of other methods to battle your `crystal-robots` and each peels back a layer to teach you more about full-stack programming.

### Fossil server for contributors

The web app is a [Fossil CGI extension](https://fossil-scm.org/home/doc/trunk/www/serverext.wiki):
Fossil serves the repository, the docs and the app, and supplies the login.
The app replies in Markdown, so it appears inside the repository's own skin.

```
shards build
scripts/install_extroot.sh /path/to/extroot      # symlinks extroot/crystal-robots -> bin/crystal-robots
fossil server crystal-robots.fossil --extroot /path/to/extroot --port 8080
```

Then browse to `http://localhost:8080/ext/crystal-robots/`: pick example robots or
paste your own, run a seeded match, watch the replay at a chosen pace
(cycles per second, 300 by default, roughly the original curses display),
step through its frames drawn in Pikchr with each robot's trail, or run a
series of matches for a score table like `crobots -m`.

To keep a robot, create a wiki page named `robot/<name>` whose Markdown
contains exactly one fenced code block; that block is the robot. It then
appears on the overview (with its first paragraph as a description and a
"fight" link), in the battle picker, and at `/ext/crystal-robots/wiki/<name>`
with its derivation and checks. Five such robots ship in `robots/*.md`
(hunter, circler, dodger, wallhugger, turret); publish them to a
repository's wiki with:

```
scripts/publish_wiki_robots.sh -R /path/to/crystal-robots.fossil
```

A CROBOTS rule worth knowing when writing one: a heading change only takes
at 50 percent speed or less. Ask for a turn while faster and the drive
disengages, so slow down first (the shipped robots show both ways).

Cycles are charged the way the CROBOTS virtual machine did: one per
operand fetch, operator, store, branch and statement, two per builtin
call, three around a user function call. `-l` limits those cycles. A rebuild is the deploy:
the CGI runs fresh on every request. To put the app in the Fossil menu, paste
`fossil-skin/mainmenu` into Admin, Skins, Main Menu. It mirrors the deployed
menu (Agents, Docs and a "Run" entry for this app); merge rather than
replace if your skin has other rows. Who may use the app is
decided by the repository's user capabilities: reading the overview and
examples needs `o` or `h` (what anonymous usually has); running battles and
parsing needs check-in (`i`); seeing saved robots needs wiki read (`j`).

#### Tournament

`/ext/crystal-robots/tournament` lets you pick robots (or **Check
everyone**) into a tournament: pool play (round-robin, win +1 / loss -1,
a refight on a tie or a no-winner fight) followed by a single-elimination
bracket (best of 3, byes for the top seeds) down to one champion. The
whole thing is stateless like a battle: every stage's outcome round-trips
through the tournament's own link, so it replays exactly and can be
shared or resumed from that link alone. Running one needs check-in (`i`),
the same permission battles need.

### Self-hosted server without Fossil

Planned: `bin/crystal-robots -p 8080` will serve the same pages directly.

### Compiled to native code with `crystal`

To setup the environment for your robots, use `prelude.cr` ...

```
crystal run --prelude=../src/prelude robot1.cr robot2.cr robot3.cr robot4.cr -- -m 500
```

### Command-line interpretation by `crystal-robots`

Using the `crystal-robots` compiler, you can perform battles by running the built-in interpreter ...

```
bin/crystal-robots -i -m 5 robot1.cr robot2.cr robot3.cr robot4.cr
```

### Compiled to WASM by `crystal-robots` and executed with `wasmer`



## Support

TODO: Write support instructions here

## Roadmap

See [docs/PLAN.md](docs/PLAN.md) for the phased development plan, the current
baseline, and the open parser-architecture decision.

## Development

One command runs everything the review pipeline runs:

```
crystal run ci.cr --                 # shards, build-docs, build, spec, format check, example builds, CLI smoke
crystal run ci.cr -- --with-wasmer   # also runs the WebAssembly specs under wasmer 4.4.0 (installed under ./.wasmer if absent)
crystal run ci.cr -- --with-wasm32   # also builds site/crystal-robots.wasm, the browser compiler (installed libs under ./.wasm32-wasi-libs if absent)
```

The pieces, if you want them separately:

```
crystal spec                       # everything except running WebAssembly (those specs are pending)
crystal spec -Dwasmer              # also runs the emitted modules with wasmer
crystal tool format --check src spec scripts
bin/crystal-robots build-docs      # crystal docs into docs-api/; the next shards build embeds them at /ext/crystal-robots/docs (shown inside the Fossil skin)
bin/crystal-robots --version       # "crystal-robots 0.0.1 (check-in <hash>)", the hash from manifest.uuid at build time
```

The wasmer runtime is optional. Wasmer 4.4.0 is the last release with a
`linux-musl` build, so pin it:

```
scripts/install_wasmer.sh v4.4.0
export WASMER_DIR=$HOME/.wasmer
```

The browser compiler (`site/`, published at
[jadonk.github.io/crystal-robots](https://jadonk.github.io/crystal-robots/)
by `.github/workflows/pages.yml`) needs the wasm32-wasi-libs sysroot to
link, pinned to release 0.0.3 the same way; `crystal run ci.cr --
--with-wasm32` installs it under `./.wasm32-wasi-libs` and builds
`site/crystal-robots.wasm` in one step (its `install_wasm32_wasi_libs`
function is the only installer, downloaded and extracted directly, no
shell script involved).

The parser design is described in [docs/PARSER.md](docs/PARSER.md); the
phased plan and current status in [docs/PLAN.md](docs/PLAN.md).

### Roadmap

See [docs/PLAN.md](docs/PLAN.md). Longer-term ideas kept from the original list:

- [ ] Fossil-like self-source-control and documentation generation/hosting
- [ ] Forks: SQL implementation in Crystal

## Contributing

The repository is Fossil, hosted at <https://ollama.openbeagle.org/crystal-robots>.

1. `fossil clone https://ollama.openbeagle.org/crystal-robots crystal-robots.fossil` and `fossil open` it.
2. Work on a branch: `fossil commit --branch my-feature -m "..."`.
3. Run `crystal run ci.cr` before asking for review; it is the same gate
   the merge pipeline runs.
4. Ask for review in the project forum. Merges to trunk are done by the
   trunk operator after the suite passes on a merge stand-in; the served
   app is rebuilt from trunk after the merge.
5. Robots, as opposed to code, need no branch: a wiki page named
   `robot/<name>` is enough (see Usage).

## License

`crystal-robots` is distributed under terms of the GNU General Public License, version 2.

This is in line with Tom Poindexter's release of `CROBOTS`. While more restrictive than
Colin Eberhardt's release of `chasm` under an MIT license, it seems to me to be better
to follow the more restrictive license. I hope that Colin agrees and if I ever complete
this, I'll be sure to engage to find a suitable compromise.

## Contributors

- [Tom Poindexter](https://github.com/tpoindex) - creator of `CROBOTS`
- [Colin Eberhardt](https://github.com/ColinEberhardt) - creator of `chasm`
- [Jason Kridner](https://github.com/jadonk) - creator and maintainer of `crystal-robots`
