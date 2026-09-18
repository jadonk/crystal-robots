require "./spec_helper"

# The golden spec: every shipped example robot parses, passes the
# checker clean, and compiles to WebAssembly without WASM_Emitter raising
# Unsupported -- the same milestone the original multipass-tokenizer
# design document (docs/PARSER.md) named for these five: "all six example
# robots reduce to the single Program glyph with correct precedence and
# associativity."
#
# None of them are *run* here: counter, rabbit, rook, sniper and target
# all loop `while true`, meant to be interleaved on a battlefield with a
# cycle limit, not executed standalone -- that engine is the next piece
# of work, not this one.
EXAMPLES = %w[counter rabbit rook sniper target hello functions]

describe "the shipped example robots" do
  EXAMPLES.each do |name|
    it "#{name}.cr parses, checks clean, and compiles" do
      source = File.read("examples/#{name}.cr")
      program = CrystalRobots::Compiler::Parser.new(source).program
      program.parsed?.should be_true

      issues = CrystalRobots::Compiler::Checker.check(program)
      issues.map(&.to_s).should eq [] of String

      CrystalRobots::Compiler::WASM_Emitter.new(program).to_wasm.size.should be > 8
    end
  end
end
