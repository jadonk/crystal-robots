require "./spec_helper"
require "../src/battle/field"

alias B = CrystalRobots::Battle

IDLE = "main(\"Idle\") do\n  while true\n    sleep\n  end\nend\n"

private def field(*sources, seed = 1_u64, limit = 3000_i64) : B::Field
  entries = sources.map_with_index { |src, i| {"r#{i}", src} }.to_a
  B::Field.new(entries, seed: seed, limit: limit)
end

describe CrystalRobots::Battle do
  it "uses the CROBOTS trig table" do
    B.lsin(0).should eq 0
    B.lsin(90).should eq 100000
    B.lsin(180).should eq 0
    B.lsin(270).should eq -100000
    B.lcos(0).should eq 100000
    B.lcos(180).should eq -100000
    B.lcos(-90).should eq 0
    B.lsin(45).should eq 70710
  end

  it "scans for the closest robot within the resolution" do
    f = field(IDLE, IDLE, IDLE)
    f.robots.each { |r| r.active = true }
    f.place(0, 100, 100)
    f.place(1, 300, 100) # 200 m due east
    f.place(2, 100, 400) # 300 m due north
    f.scan(f.robots[0], 0, 5).should eq 200
    f.scan(f.robots[0], 90, 0).should eq 300
    f.scan(f.robots[0], 180, 10).should eq 0
    f.scan(f.robots[0], 359, 2).should eq 200 # wraps around 0
    f.scan(f.robots[1], 180, 1).should eq 200
  end

  it "accelerates, turns only when slow, and takes wall damage" do
    f = field(IDLE)
    r = f.robots[0]
    r.active = true
    f.place(0, 950, 500)
    f.drive(r, 0, 100).should eq 1
    f.move_robots
    r.speed.should eq 10
    r.x.should eq 9500 # 7 clicks of range truncate to 0 meters, as in CROBOTS
    5.times { f.move_robots }
    r.speed.should eq 60
    r.x.should be > 9500
    f.drive(r, 90, 100)
    f.move_robots
    r.heading.should eq 0 # too fast to turn: the drive disengages instead
    r.d_speed.should eq 0
    f.drive(r, 0, 100) # resume toward the east wall
    40.times { f.move_robots }
    r.x.should eq B::MAX_X * B::CLICK - 1
    r.speed.should eq 0
    r.damage.should eq B::COLLISION
  end

  it "fires, reloads, and damages robots near the explosion" do
    f = field(IDLE, IDLE)
    a, b = f.robots
    f.robots.each { |r| r.active = true }
    f.place(0, 100, 100)
    f.place(1, 300, 100)
    f.cannon(a, 0, 200).should eq 1
    f.cannon(a, 0, 200).should eq 0 # reloading
    a.reload.should eq B::RELOAD
    4.times { f.move_missiles }
    a.missiles[0].stat.exploding?.should be_true
    b.damage.should eq 10 # direct hit
    a.damage.should eq 0
    B::EXP_COUNT.times { f.count_missiles }
    a.missiles[0].stat.avail?.should be_true
  end

  it "runs a deterministic match and records frames" do
    counter = File.read("examples/counter.cr")
    target = File.read("examples/target.cr")
    one = field(counter, target, limit: 6000_i64).run
    two = field(counter, target, limit: 6000_i64).run
    one.frames.size.should be > 2
    one.frames.map(&.robots).should eq two.frames.map(&.robots)
    one.cycles.should eq two.cycles
    one.robots.each { |r| r.cycles.should be > 0 }
    one.robots[0].name.should eq "r0"
    three = field(counter, target, seed: 7_u64, limit: 6000_i64).run
    three.frames[0].robots.should_not eq one.frames[0].robots
  end

  it "reports parse errors without stopping the others" do
    f = field("if x\n", IDLE, limit: 300_i64).run
    f.robots[0].error.not_nil!.should contain "Cannot reduce"
    f.robots[0].active.should be_false
    f.robots[1].active.should be_true
    f.winner.not_nil!.name.should eq "r1"
  end

  it "restarts a program that finishes, like CROBOTS" do
    f = field("puts 1\n", IDLE, limit: 300_i64).run
    f.robots[0].restarts.should be > 1
    f.robots[0].output.first.should eq "1"
  end
end
