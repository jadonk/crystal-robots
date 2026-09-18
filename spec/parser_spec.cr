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

  it "parses builtins of every arity, bare and parenthesized" do
    Parser.new("puts damage\n").program.parsed?.should be_true
    Parser.new("puts scan 3, 4\n").program.parsed?.should be_true
    Parser.new("puts sqrt 16\n").program.parsed?.should be_true
    Parser.new("puts sqrt(16)\n").program.parsed?.should be_true
    Parser.new("puts scan(3, 4)\n").program.parsed?.should be_true
  end

  it "parses def, calls with arguments, and return" do
    Parser.new("def go(a, b)\na + b\nend\nputs go(1, 2)\n").program.parsed?.should be_true
    Parser.new("def zero\n0\nend\nputs zero()\n").program.parsed?.should be_true
    Parser.new("def early(n)\nreturn n\nend\n").program.parsed?.should be_true
  end

  it "does not read a def header as a call" do
    Parser.new("def go(a, b)\nreturn a\nend\n").program.parsed?.should be_true
  end

  it "parses main(\"Name\") do ... end" do
    Parser.new(%(main("Sniper") do\nputs 1\nend\n)).program.parsed?.should be_true
  end

  it "parses case, when and else" do
    Parser.new("case 1\nwhen 1\nputs 1\nend\n").program.parsed?.should be_true
    Parser.new("case 1\nwhen 1\nputs 1\nwhen 2\nputs 2\nelse\nputs 3\nend\n").program.parsed?.should be_true
  end

  it "parses if, elsif and else" do
    Parser.new("if 1 == 1\nputs 1\nend\n").program.parsed?.should be_true
    Parser.new("if 1 == 1\nputs 1\nelse\nputs 2\nend\n").program.parsed?.should be_true
    Parser.new("if 1 == 1\nputs 1\nelsif 2 == 2\nputs 2\nelse\nputs 3\nend\n").program.parsed?.should be_true
  end

  it "parses a plain top-level assignment and a bare zero-argument call" do
    Parser.new("C1X = 10\nputs C1X\n").program.parsed?.should be_true
    Parser.new("def go\n1\nend\nputs go\n").program.parsed?.should be_true
  end

  it "parses && || and ^ at a lower precedence than comparisons" do
    Parser.new("puts 1 < 2 && 3 < 4\n").program.parsed?.should be_true
    Parser.new("puts 1 < 2 || 3 < 4\n").program.parsed?.should be_true
    Parser.new("puts 1 ^ 2\n").program.parsed?.should be_true
  end

  it "parses an assignment inside a condition, and a bare builtin call as a call argument" do
    Parser.new("i = 3\nwhile (n = i) > 0\ni -= 1\nend\n").program.parsed?.should be_true
    Parser.new("def sum(a, b)\na + b\nend\nputs sum(sqrt 16, sqrt 9)\n").program.parsed?.should be_true
  end

  it "parses compound assignment" do
    Parser.new("global(i, 0)\ni += 1\ni -= 1\ni *= 2\ni %= 3\n").program.parsed?.should be_true
  end

  it "parses comments and true/false literals" do
    Parser.new("# a whole-line comment\nputs true # trailing too\nputs false\n").program.parsed?.should be_true
  end

  it "parses precedence, associativity and parenthesized expressions" do
    Parser.new("puts 1 + 2 * 3\n").program.parsed?.should be_true
    Parser.new("puts 1 - 2 - 3\n").program.parsed?.should be_true
    Parser.new("puts (1 + 2) * 3\n").program.parsed?.should be_true
    Parser.new("puts -5 + 2\n").program.parsed?.should be_true
  end
end
