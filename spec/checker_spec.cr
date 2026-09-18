require "./spec_helper"

alias Checker = CrystalRobots::Compiler::Checker

private def issues(source : String) : Array(String)
  program = CrystalRobots::Compiler::Parser.new(source).program
  Checker.check(program).map(&.message)
end

describe Checker do
  it "finds nothing wrong with a clean program" do
    issues("global(count, 0)\nputs count\n").should be_empty
  end

  it "flags an undefined variable" do
    issues("puts mystery\n").should eq ["undefined variable mystery"]
  end

  it "flags an undefined function" do
    issues("puts go(1)\n").should eq ["undefined function go"]
  end

  it "flags a call with the wrong number of arguments" do
    issues("def go(a, b)\na + b\nend\nputs go(1)\n").should eq ["go takes 2 arguments, given 1"]
  end

  it "flags return outside of a function" do
    issues("return\n").should eq ["return outside of a function"]
  end

  it "flags break outside of a loop" do
    issues("break\n").should eq ["break outside of a loop"]
  end

  it "flags a duplicate def" do
    issues("def go\n1\nend\ndef go\n2\nend\n").should eq ["go is already defined"]
  end

  it "allows a parameter and a name assigned in the body as values" do
    issues("def go(a)\nb = a + 1\nb\nend\nputs go(1)\n").should be_empty
  end

  it "allows break inside a while loop and return inside a function" do
    issues("while 1 == 1\nbreak\nend\n").should be_empty
    issues("def go\nreturn 1\nend\nputs go()\n").should be_empty
  end

  it "allows a function to call one defined later in the source" do
    issues("def first\nsecond()\nend\ndef second\n1\nend\nputs first()\n").should be_empty
  end

  it "allows a plain top-level assignment as an implicit global constant" do
    issues("C1X = 10\nputs C1X\n").should be_empty
  end

  it "allows a bare call to a zero-argument function" do
    issues("def go\n1\nend\nputs go\n").should be_empty
  end

  it "allows an assignment inside a condition, at the top level and inside main" do
    issues("i = 3\nwhile (n = i) > 0\ni -= 1\nend\nputs n\n").should be_empty
    issues(%(main("Test") do\nwhile (n = 1) > 0\nbreak\nend\nputs n\nend\n)).should be_empty
  end

  it "reports every issue, not just the first" do
    issues("puts mystery\nputs go(1)\n").should eq ["undefined variable mystery", "undefined function go"]
  end
end
