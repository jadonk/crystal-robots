# Trunk keeps the Type enum and the Program/Node classes in this same
# file; this history already has both, as src/compiler/program.cr
# (confirmed field-for-field identical: the same reserved glyph per
# token kind, the same Node/Program shape, derivation, emitted). What
# is left to port here is behavior, not layout: two module-level
# convenience wrappers over source text, used by src/browser.cr and by
# specs that want a one-line compile or interpret without touching
# Parser/Interpreter/WASM_Emitter directly.
require "./parser"
require "./checker"
require "./interpreter"
require "./wasm_emitter"

module CrystalRobots::Compiler
  # Parse and run `source` in the interpreter against a `NullHost`.
  # Returns the total cycles charged.
  def self.interpret(source : String) : Int64
    program = Parser.new(source).program
    Interpreter.execute(program, NullHost.new)
  end

  # Parse `source` and emit a WebAssembly module.
  def self.compile_to_wasm(source : String) : Bytes
    program = Parser.new(source).program
    WASM_Emitter.new(program).to_wasm
  end
end
