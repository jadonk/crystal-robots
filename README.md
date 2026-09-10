# crystal-robots

A great way to learn about programming with a simple Ruby-like syntax. Write programs to battle
it out with other programs on a virtual battlefield. Then, learn about how programming languages
turn your code into instructions a machine can understand.

`crystal-robots` is inspired and derived from:
*  [CROBOTS - a programming game, for programmers, or aspiring programmers](http://tpoindex.github.io/crobots/),
* the [Crystal Programming Language - A language for humans and computers](https://crystal-lang.org/),
* and [chasm - a simple compile-to-WASM language](https://github.com/ColinEberhardt/chasm).

`crystal-robots` is my exploration of depending on my own programming tools, taking control over a programming
language itself.

* [Source Code](https://openbeagle.org/jkridner/crystal-robots)
* [Github Mirror](https://github.com/jadonk/crystal-robots)
* [Documentation and online hosting](https://jkridner.beagleboard.io/crystal-robots)

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

The primary method for using `crystal-robots` is by using my hosted server. The compiler is built into the web page. You can provide sources for the various robots and watch them battle it out.

There are a lot of other methods to battle your `crystal-robots` and each peels back a layer to teach you more about full-stack programming.

### Hosted by Fossil (the primary way)

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
decided by the repository's user capabilities: reading needs `o` or `h`
(what anonymous usually has), saving robots (later) needs check-in (`i`).

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

```
crystal spec                       # everything except running WebAssembly
crystal spec -Dwasmer              # also runs the emitted modules with wasmer
crystal tool format --check src spec scripts
```

The wasmer runtime is optional. Wasmer 4.4.0 is the last release with a
`linux-musl` build, so pin it:

```
scripts/install_wasmer.sh v4.4.0
export WASMER_DIR=$HOME/.wasmer
```

The parser design is described in [docs/PARSER.md](docs/PARSER.md); the
phased plan and current status in [docs/PLAN.md](docs/PLAN.md).

### Roadmap

See [docs/PLAN.md](docs/PLAN.md). Longer-term ideas kept from the original list:

- [ ] Fossil-like self-source-control and documentation generation/hosting
- [ ] Forks: SQL implementation in Crystal

## Contributing

1. Fork it (<https://openbeagle.org/jkridner/crystal-robots/-/forks/new>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Merge Request

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
