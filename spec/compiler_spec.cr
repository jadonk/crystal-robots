require "./spec_helper"
require "../src/compiler/compiler"

alias Compiler = CrystalRobots::Compiler

describe "CrystalRobots::Compiler module functions" do
  it ".interpret parses and runs source, returning the cycles charged" do
    cycles = Compiler.interpret("puts 1 + 2\n")
    cycles.should be > 0_i64
    cycles.should eq CrystalRobots::Compiler::Interpreter.execute(
      CrystalRobots::Compiler::Parser.new("puts 1 + 2\n").program, CrystalRobots::Compiler::NullHost.new
    )
  end

  it ".compile_to_wasm parses source and emits the same bytes WASM_Emitter would" do
    source = "puts 1 + 2\n"
    wasm = Compiler.compile_to_wasm(source)
    expected = CrystalRobots::Compiler::WASM_Emitter.new(CrystalRobots::Compiler::Parser.new(source).program).to_wasm
    wasm.should eq expected
  end
end
