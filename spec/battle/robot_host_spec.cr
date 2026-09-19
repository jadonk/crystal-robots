require "../spec_helper"

alias RobotHost = CrystalRobots::Battle::RobotHost
alias BattleField = CrystalRobots::Battle::Field

describe RobotHost do
  it "reads position, speed and damage from the field's own robot" do
    field = BattleField.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.x = 1234
    robot.y = 5678
    robot.speed = 42
    robot.damage = 7
    host = RobotHost.new(field, 0)
    host.loc_x.should eq robot.x // CrystalRobots::Battle::CLICK
    host.loc_y.should eq robot.y // CrystalRobots::Battle::CLICK
    host.speed.should eq 42
    host.damage.should eq 7
  end

  it "drive sets the field robot's desired heading and speed" do
    field = BattleField.new(["a"], seed: 1)
    RobotHost.new(field, 0).drive(90, 50)
    field.robots[0].d_heading.should eq 90
    field.robots[0].d_speed.should eq 50
  end

  it "cannon fires through the field, honoring the reload gate" do
    field = BattleField.new(["a"], seed: 1)
    host = RobotHost.new(field, 0)
    host.cannon(0, 100).should eq 1
    host.cannon(0, 100).should eq 0 # reloading
  end

  it "scan and rand delegate to the field" do
    field = BattleField.new(["a", "b"], seed: 1)
    a, b = field.robots
    a.x = a.org_x = 500
    a.y = a.org_y = 500
    b.x = b.org_x = 500 + CrystalRobots::Battle::CLICK * 50
    b.y = b.org_y = 500
    RobotHost.new(field, 0).scan(0, 5).should eq 50
    RobotHost.new(field, 0).rand(1).should eq 0
  end

  it "sin/cos/tan are scaled by 100000 and atan takes a scaled ratio, matching real CROBOTS" do
    host = RobotHost.new(BattleField.new(["a"], seed: 1), 0)
    host.sin(90).should eq 100_000
    host.cos(0).should eq 100_000
    host.atan(100_000).should eq 45 # atan(1) = 45 degrees
  end

  it "runs a real robot's interpreter against the battlefield" do
    source = <<-ROBOT
      main("Test") do
      drive(45, 100)
      puts damage
      puts speed
      end
      ROBOT
    program = CrystalRobots::Compiler::Parser.new(source).program
    field = BattleField.new(["Test"], seed: 1)
    host = RobotHost.new(field, 0)
    CrystalRobots::Compiler::Interpreter.execute(program, host)
    field.robots[0].d_heading.should eq 45
    field.robots[0].d_speed.should eq 100
  end
end
