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

TODO: Write installation instructions here

## Usage

TODO: Write usage instructions here

The primary method for using `crystal-robots` is by using my hosted server. The compiler is built into the web page. You can provide sources for the various robots and watch them battle it out.

There are a lot of other methods to battle your `crystal-robots` and each peels back a layer to teach you more about full-stack programming.

### My hosted server

Browse to https://jkridner.beagleboard.io/crystal-robots and ...

### Self-hosted server

Start your own server by invoking `crystal-robots` and specifying a port ...

```
bin/crystal-robots -p 8080
```

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

TODO: Describe the development roadmap here

## Development

TODO: Write development instructions here

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
