# TODO: Write documentation for `CrystalRobots::Compiler`
require "./wasm_emitter.cr"
require "./tokenizer.cr"

module CrystalRobots::Compiler
  # Crystal Robots compiler
  #
  # ## Description
  #
  # The Crystal Robots compiler accepts a limited subset of the [Crystal Programming Language](https://crystal-lang.org). The entire program must be a single source file. No macro operations are supported. The compile machine code targets [WebAssembly](https://webassembly.org/) and calls various functions in a browser-based simulation
  #
  # ## Features missing
  #
  class Compiler
    @src : String
    @code : Bytes
    @ast : Program
    @tokenizer : Tokenizer

    def initialize
      @src = ""
      @code = Bytes[]
      @tokenizer = Tokenizer.new(@src)
      x = [] of Tokenizer::Token
      @ast = Program.new([x])
    end

    def program
      @ast
    end

    def compile_to_wasm(src)
      @src = src
      @tokenizer = Tokenizer.new(src)
      @ast = @tokenizer.parse
      @code = WASM_Emitter.new(@ast).to_wasm
      @code
    end
  end

  struct Program
    property ast

    def initialize(@ast : Array(Array(Tokenizer::Token)))
    end

    def <<(tokens : Array(Tokenizer::Token))
      @ast << tokens
    end
  end
end
