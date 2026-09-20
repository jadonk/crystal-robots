require "./spec_helper"
require "../src/battle/field"

# The robots shipped in robots/*.md are published as wiki pages `robot/<name>`.
# Each must be a valid page (one code block), parse, pass the checker, and
# survive a short match without failing.
describe "robots/*.md" do
  files = Dir.glob("robots/*.md").sort
  it "ships a handful of them" do
    files.size.should be >= 4
  end

  files.each do |file|
    name = File.basename(file, ".md")
    it "#{name} is a well-formed saved robot that plays" do
      File.read(file).lstrip.starts_with?("```").should be_false
      src = File.read(file).match(/```[a-z]*\n(.*?)```/m).not_nil![1]
      program = C::Parser.new(src).program
      C::Checker.check(program).should be_empty
      field = CrystalRobots::Battle::Field.new([{name, src}, {"target", File.read("examples/target.cr")}],
        seed: 3_u64, limit: 60_000_i64, positions: [{700, 500}, {500, 500}])
      field.run
      robot = field.robots[0]
      robot.error.should be_nil
      robot.cycles.should be > 1000
      robot.fired.should be_true # a target 200 m away must be found and shot
      field.robots[1].damage.should be > 0
    end
  end
end
