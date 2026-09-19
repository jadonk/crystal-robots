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

  it "fires a missile, then refuses while reloading" do
    field = Field.new(["a"], seed: 1)
    field.fire_missile(0, 90, 100).should be_true
    field.missiles[0].count(&.status.flying?).should eq 1
    field.fire_missile(0, 90, 100).should be_false # still reloading
  end

  it "reloads after RELOAD motion cycles, filling the second slot" do
    field = Field.new(["a"], seed: 1)
    field.fire_missile(0, 90, 700) # long range: still flying when reload clears
    CrystalRobots::Battle::RELOAD.times { field.move_robots }
    field.fire_missile(0, 90, 100).should be_true
    field.missiles[0].count(&.status.flying?).should eq 2
  end

  it "reports success without firing on a negative distance, a real CROBOTS quirk" do
    field = Field.new(["a"], seed: 1)
    field.fire_missile(0, 90, -1).should be_true
    field.missiles[0].none?(&.status.flying?).should be_true
  end

  it "flies a missile toward its target range, then explodes it" do
    field = Field.new(["a"], seed: 1)
    field.fire_missile(0, 0, 50) # 50 meters east, well within one motion cycle
    missile = field.missiles[0][0]
    field.move_missiles
    missile.status.exploding?.should be_true
    missile.cur_x.should be > missile.beg_x
  end

  it "damages a robot caught in a direct hit, and ages the explosion back to available" do
    field = Field.new(["shooter", "target"], seed: 1)
    shooter, target = field.robots
    target.x = shooter.x + (CrystalRobots::Battle::CLICK * 2) # 2 meters east, within DIRECT_RANGE
    target.y = shooter.y
    field.fire_missile(0, 0, 50)
    field.move_missiles
    target.damage.should eq CrystalRobots::Battle::DIRECT_HIT

    missile = field.missiles[0][0]
    (CrystalRobots::Battle::EXP_COUNT + 1).times { field.move_missiles }
    missile.status.avail?.should be_true
  end

  it "scans and finds a robot dead ahead" do
    field = Field.new(["a", "b"], seed: 1)
    a, b = field.robots
    a.x = a.org_x = 500
    a.y = a.org_y = 500
    b.x = b.org_x = 500 + CrystalRobots::Battle::CLICK * 100 # 100m east
    b.y = b.org_y = 500
    field.scan(0, 0, 5).should eq 100
  end

  it "scans and finds nothing outside the resolution cone" do
    field = Field.new(["a", "b"], seed: 1)
    a, b = field.robots
    a.x = a.org_x = 500
    a.y = a.org_y = 500
    b.x = b.org_x = 500
    b.y = b.org_y = 500 + CrystalRobots::Battle::CLICK * 100 # 100m north, not east
    field.scan(0, 0, 5).should eq 0
  end

  it "does not damage a robot far outside the blast radius" do
    field = Field.new(["shooter", "target"], seed: 1)
    shooter, target = field.robots
    shooter.x = shooter.org_x = 500
    shooter.y = shooter.org_y = 500
    target.x = 5
    target.y = 5
    field.fire_missile(0, 0, 50)
    field.move_missiles
    target.damage.should eq 0
  end
end
