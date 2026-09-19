require "../spec_helper"

alias Match = CrystalRobots::Battle::Match

private def program(source : String) : CrystalRobots::Compiler::Program
  CrystalRobots::Compiler::Parser.new(source).program
end

describe Match do
  it "interleaves two robots, each getting a turn every round" do
    a = program("global(i, 0)\nwhile true\ni += 1\nend\n")
    b = program("global(j, 0)\nwhile true\nj += 1\nj += 1\nend\n")
    field = BattleField.new(["a", "b"], seed: 1)
    match = Match.new(field, [a, b], cycle_limit: 20)
    match.run
    match.rounds.should eq 20
  end

  it "stops early once only one robot is left standing" do
    dies = program(<<-ROBOT)
      global(i, 0)
      while true
      i += 1
      end
      ROBOT
    survives = program(<<-ROBOT)
      global(i, 0)
      while true
      i += 1
      end
      ROBOT
    field = BattleField.new(["dies", "survives"], seed: 1)
    field.robots[0].status = :dead # already dead before the match starts
    match = Match.new(field, [dies, survives], cycle_limit: 1000)
    match.run
    match.rounds.should eq 0 # never > 1 alive to begin with
  end

  it "stops at the next motion cycle once damage reaches 100 mid-match" do
    dies = program("global(i, 0)\nwhile true\ni += 1\nend\n")
    survives = program("global(j, 0)\nwhile true\nj += 1\nend\n")
    field = BattleField.new(["dies", "survives"], seed: 1)
    field.robots[0].damage = 100 # takes until the next move_robots to register
    match = Match.new(field, [dies, survives], cycle_limit: 1000)
    match.run
    match.rounds.should eq CrystalRobots::Battle::MOTION_CYCLES
    field.robots[0].alive?.should be_false
  end

  it "runs a real robot (target.cr) cooperatively without hanging" do
    source = File.read("examples/target.cr")
    field = BattleField.new(["Target", "Other"], seed: 1)
    other = program("while true\nend\n")
    match = Match.new(field, [program(source), other], cycle_limit: 50)
    match.run
    match.rounds.should eq 50
  end

  it "marks a robot dead on a runtime crash, rather than hanging the match" do
    crasher = program("puts 1 / 0\nwhile true\nend\n") # divide by zero: a known interpreter gap, raises
    survives = program("global(i, 0)\nwhile true\ni += 1\nend\n")
    field = BattleField.new(["crasher", "survives"], seed: 1)
    match = Match.new(field, [crasher, survives], cycle_limit: 1000)
    match.run
    field.robots[0].alive?.should be_false
    match.rounds.should be > 0
  end

  it "drives a robot to actually move via the field" do
    mover = program(<<-ROBOT)
      main("Mover") do
      drive(0, 100)
      while true
      end
      end
      ROBOT
    waiter = program("while true\nend\n")
    field = BattleField.new(["Mover", "Waiter"], seed: 1)
    starting_x = field.robots[0].x
    match = Match.new(field, [mover, waiter], cycle_limit: CrystalRobots::Battle::MOTION_CYCLES * 3)
    match.run
    field.robots[0].x.should_not eq starting_x
  end
end
