require "./spec_helper"

alias Parser = CrystalRobots::Compiler::Parser

describe Parser do
  it "reduces one puts statement to the Program glyph" do
    program = Parser.new("puts 42\n").program
    program.parsed?.should be_true
  end

  it "reduces several puts statements" do
    program = Parser.new("puts 1\nputs 2\nputs 3\n").program
    program.parsed?.should be_true
  end

  it "prints the derivation, one line per pass" do
    program = Parser.new("puts 42\n").program
    program.derivation.should eq <<-DERIVATION + "\n"
        0 lex         ∊№⏎
        1 command1    😑⏎
        2 exprstmt    ❢
        3 program     ⏹
      DERIVATION
  end

  it "raises when nothing reduces the input" do
    expect_raises(Parser::Error) { Parser.new(")\n") }
  end

  it "parses a global declaration and a reference to it" do
    Parser.new("global(count, 0)\nputs count\n").program.parsed?.should be_true
  end

  it "parses assignment as a statement" do
    Parser.new("global(count, 0)\ncount = count + 1\nputs count\n").program.parsed?.should be_true
  end

  it "parses while, until and break" do
    Parser.new("global(i, 0)\nwhile i < 5\ni = i + 1\nend\n").program.parsed?.should be_true
    Parser.new("global(i, 5)\nuntil i == 0\ni = i - 1\nend\n").program.parsed?.should be_true
    Parser.new("global(i, 0)\nwhile i < 5\nbreak\nend\n").program.parsed?.should be_true
  end

  it "parses comparisons at a lower precedence than arithmetic" do
    Parser.new("puts 1 + 2 < 3 * 4\n").program.parsed?.should be_true
    Parser.new("puts 1 < 2 == 3 < 4\n").program.parsed?.should be_true
  end

  it "parses builtins of every arity" do
    Parser.new("puts damage\n").program.parsed?.should be_true
    Parser.new("puts scan 3, 4\n").program.parsed?.should be_true
    Parser.new("puts sqrt 16\n").program.parsed?.should be_true
  end

  it "parses if, elsif and else" do
    Parser.new("if 1 == 1\nputs 1\nend\n").program.parsed?.should be_true
    Parser.new("if 1 == 1\nputs 1\nelse\nputs 2\nend\n").program.parsed?.should be_true
    Parser.new("if 1 == 1\nputs 1\nelsif 2 == 2\nputs 2\nelse\nputs 3\nend\n").program.parsed?.should be_true
  end

  it "parses precedence, associativity and parenthesized expressions" do
    Parser.new("puts 1 + 2 * 3\n").program.parsed?.should be_true
    Parser.new("puts 1 - 2 - 3\n").program.parsed?.should be_true
    Parser.new("puts (1 + 2) * 3\n").program.parsed?.should be_true
    Parser.new("puts -5 + 2\n").program.parsed?.should be_true
  end
end
