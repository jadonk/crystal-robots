require "../spec_helper"

alias Field = CrystalRobots::Battle::Field

describe Field do
  it "places each robot in its own quadrant of the field" do
    field = Field.new(["a", "b", "c", "d"], seed: 1)
    half_x = CrystalRobots::Battle::MAX_X * CrystalRobots::Battle::CLICK // 2
    half_y = CrystalRobots::Battle::MAX_Y * CrystalRobots::Battle::CLICK // 2
    quadrants = field.robots.map { |r| {r.x < half_x ? 0 : 1, r.y < half_y ? 0 : 1} }
    quadrants.uniq.size.should eq 4
  end

  it "accelerates toward the desired speed, not instantly" do
    field = Field.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.d_speed = 100
    field.move_robots
    robot.speed.should eq CrystalRobots::Battle::ACCEL
    field.move_robots
    robot.speed.should eq CrystalRobots::Battle::ACCEL * 2
  end

  it "decelerates toward a lower desired speed" do
    field = Field.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.speed = robot.accel = 50
    robot.d_speed = 0
    field.move_robots
    robot.speed.should eq 50 - CrystalRobots::Battle::ACCEL
  end

  it "changes heading only at or below TURN_SPEED, otherwise cancels the speed change" do
    field = Field.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.speed = robot.accel = robot.d_speed = 40
    robot.heading = 0
    robot.d_heading = 90
    field.move_robots
    robot.heading.should eq 90

    robot.speed = robot.accel = robot.d_speed = 80
    robot.heading = 90
    robot.d_heading = 180
    field.move_robots
    robot.heading.should eq 90 # too fast to turn
    robot.d_speed.should eq 0  # the turn attempt cancels the speed instead
  end

  it "moves in the direction of its heading once driving" do
    field = Field.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.x = robot.org_x = 500
    robot.y = robot.org_y = 500
    robot.heading = robot.d_heading = 0 # due "east"
    robot.speed = robot.accel = robot.d_speed = 100
    field.move_robots
    robot.x.should be > 500
    robot.y.should eq 500
  end

  it "stops and damages a robot that drives into a wall" do
    field = Field.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.x = robot.org_x = CrystalRobots::Battle::MAX_X * CrystalRobots::Battle::CLICK - 1
    robot.y = robot.org_y = 500
    robot.heading = robot.d_heading = 0
    robot.speed = robot.accel = robot.d_speed = 100
    10.times { field.move_robots }
    robot.speed.should eq 0
    robot.damage.should eq CrystalRobots::Battle::COLLISION
  end

  it "stops and damages both robots on collision" do
    field = Field.new(["a", "b"], seed: 1)
    a, b = field.robots
    a.x = a.org_x = 500
    a.y = a.org_y = 500
    b.x = b.org_x = 500
    b.y = b.org_y = 505 # within one click
    a.heading = a.d_heading = 0
    a.speed = a.accel = a.d_speed = 30
    field.move_robots
    a.damage.should eq CrystalRobots::Battle::COLLISION
    b.damage.should eq CrystalRobots::Battle::COLLISION
    a.speed.should eq 0
  end

  it "kills a robot whose damage reaches 100" do
    field = Field.new(["a"], seed: 1)
    robot = field.robots[0]
    robot.damage = 100
    field.move_robots
    robot.alive?.should be_false
  end
end
