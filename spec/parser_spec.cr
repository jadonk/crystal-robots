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

  it "raises with the offending word for anything else" do
    expect_raises(Parser::Error) { Parser.new("banana\n") }
  end

  it "parses precedence, associativity and parenthesized expressions" do
    Parser.new("puts 1 + 2 * 3\n").program.parsed?.should be_true
    Parser.new("puts 1 - 2 - 3\n").program.parsed?.should be_true
    Parser.new("puts (1 + 2) * 3\n").program.parsed?.should be_true
    Parser.new("puts -5 + 2\n").program.parsed?.should be_true
  end
end
