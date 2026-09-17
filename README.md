# crystal-robots

A great way to learn about programming with a simple Ruby-like syntax. Write programs to battle
it out with other programs on a virtual battlefield. Then, learn about how programming languages
turn your code into instructions a machine can understand — by building the compiler yourself,
one working commit at a time.

`crystal-robots` is inspired and derived from:
* [CROBOTS - a programming game, for programmers, or aspiring programmers](http://tpoindex.github.io/crobots/),
* the [Crystal Programming Language - A language for humans and computers](https://crystal-lang.org/),
* and [chasm - a simple compile-to-WASM language](https://github.com/ColinEberhardt/chasm), whose
  [blog post](https://blog.scottlogic.com/2019/05/17/webassembly-compiler.html) and commit-by-commit
  history this project's own history is modeled on.

This repository's check-in history *is* the tutorial: every commit compiles, every commit is
demonstrated by a `crystal spec` example or a `crystal run`, and each one adds exactly one
feature. See [docs/PLAN.md](docs/PLAN.md) for the full table of contents and
[docs/PARSER.md](docs/PARSER.md) for the parser design the history builds toward.

* [Source, docs and the hosted app](https://ollama.openbeagle.org/crystal-robots) (Fossil, development)
* Mirrors: [GitLab](https://openbeagle.org/jkridner/crystal-robots), [GitHub](https://github.com/jadonk/crystal-robots)
* Static, in-browser hosting: [jkridner.beagleboard.io/crystal-robots](https://jkridner.beagleboard.io/crystal-robots/), [jadonk.github.io/crystal-robots](https://jadonk.github.io/crystal-robots)
* Blog: [beagleboard.org/blog](https://www.beagleboard.org/blog)

## Following along

```
fossil clone https://ollama.openbeagle.org/crystal-robots crystal-robots.fossil
fossil open crystal-robots.fossil
fossil timeline    # read it oldest-first for the tutorial order
```

Each check-in message names the feature it adds. Checking out any one of them gives you a
project that builds and passes its specs:

```
crystal spec
```

## License

`crystal-robots` is distributed under terms of the GNU General Public License, version 2.

## Contributors

- [Tom Poindexter](https://github.com/tpoindex) - creator of `CROBOTS`
- [Colin Eberhardt](https://github.com/ColinEberhardt) - creator of `chasm`
- [Jason Kridner](https://github.com/jadonk) - creator and maintainer of `crystal-robots`
