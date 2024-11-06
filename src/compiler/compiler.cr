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
    @src : String | Nil
    @code : Bytes
    @ast : Program
    @tokens : Array(Tokenizer::Token) | Nil

    def initialize
      @code = Bytes[]
      @ast = Program.new
    end

    def program
      @ast
    end

    def compile_to_wasm(src)
      @src = src
      @tokens = Tokenizer.new(src).tokens
      # @ast = parse(@tokens)
      @code = WASM_Emitter.new(@ast).to_wasm
      @code
    end
  end

  struct Program
  end
end
