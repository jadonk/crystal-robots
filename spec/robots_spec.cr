require "./spec_helper"

# The robots shipped in robots/*.md. Each is a Markdown page with exactly one
# code block, and that block must parse and pass the checker.
FENCE = /^(`{3,})[^\n]*\n(.*?)\n\1[ \t]*$/m

describe "robots/*.md" do
  files = Dir.glob("robots/*.md").sort

  it "ships a handful of them" do
    files.size.should be >= 4
  end

  files.each do |file|
    name = File.basename(file, ".md")
    it "#{name} has one code block that parses and checks clean" do
      blocks = File.read(file).scan(FENCE)
      blocks.size.should eq 1
      program = CrystalRobots::Compiler::Parser.new(blocks[0][2]).program
      CrystalRobots::Compiler::Checker.check(program).should be_empty
    end
  end
end
