require "./spec_helper"
require "../src/battle/field"
require "../src/battle/step_robot"

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
    f.cannon(a, 45, 200).should eq 1
    a.cannon_dir.should eq 45
    a.fired.should be_true
    a.state.cannon.should eq 45
    a.cannon_dir = 0 # keep the rest of the test on the x axis
    a.missiles[0].head = 0
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

  it "does not fill the interpreter's shared puts buffer" do
    CrystalRobots::Compiler::Interpreter.puts_clear
    field("puts 1\n", IDLE, limit: 3000_i64).run
    CrystalRobots::Compiler::Interpreter.puts_out.should eq ""
  end

  it "marks a robot failed after repeated runtime errors instead of scoring it" do
    recursive = "def f(n)\n  f(n + 1)\nend\nmain(\"R\") do\n  f(1)\nend\n"
    f = field(recursive, IDLE, limit: 200_000_i64).run
    f.robots[0].error.not_nil!.should contain "call depth exceeded"
    f.robots[0].active.should be_false
    f.winner.not_nil!.name.should eq "r1"
  end

  it "survives extreme builtin arguments" do
    f = field(IDLE, IDLE)
    f.robots.each { |r| r.active = true }
    f.place(0, 100, 100)
    f.place(1, 300, 100)
    # Int32::MIN normalizes to 2147483648 % 360 = 128 degrees, nothing there
    f.scan(f.robots[0], Int32::MIN, Int32::MIN).should eq 0
    f.scan(f.robots[0], Int32::MAX - 127, Int32::MAX).should eq 200 # 2147483520 % 360 = 0
    f.drive(f.robots[0], Int32::MIN, Int32::MAX).should eq 1
    f.robots[0].d_heading.should eq(Int32::MIN.to_i64.abs % 360)
    f.robots[0].d_speed.should eq 100
    f.cannon(f.robots[0], Int32::MIN, Int32::MAX).should eq 1
    f.move_missiles
  end

  it "keeps missile identity in frames" do
    f = field("main(\"A\") do\n  cannon(0, 100)\n  while true\n    sleep\n  end\nend\n", IDLE, limit: 600_i64)
    f.run
    seen = f.frames.flat_map(&.missiles)
    seen.should_not be_empty
    seen.map(&.owner).uniq.should eq [0]
    seen.map(&.slot).uniq.should eq [0]
  end

  # Phase 6 (ticket a83cd0a90f): a tight frame budget must still show every
  # shot's impact, not just whatever the fixed downsample interval happens
  # to land on -- the maintainer's complaint that cannon fire and impacts
  # fall between samples. Point-blank range (5 m) means a missile explodes
  # the same or next motion update it is fired, so counting recorded
  # frames with an exploding missile is a reliable proxy for "a shot
  # landed". `RELOAD` (15 motion cycles) between shots keeps successive
  # impacts from landing on the same recorded cycle.
  it "never drops a frame with a cannon-fire event, however tight the frame budget" do
    shooter = "main(\"S\") do\n  while true\n    cannon(0, 5)\n    sleep\n  end\nend\n"
    f = B::Field.new([{"s", shooter}, {"i", IDLE}], seed: 1_u64, limit: 30_000_i64, max_frames: 2).run
    impacts = f.frames.count { |fr| fr.missiles.any?(&.exploding) }
    impacts.should be >= 10
    f.frames.size.should be > 2 # a budget of 2 alone could never have kept this many
  end

  # Same guarantee for `run_stepwise` (`src/battle/step_robot.cr`), the
  # non-fiber engine `crd_battle_run` uses on wasm32 -- both engines share
  # `Field#move_robots`/`move_missiles`/`cannon`/`scan`, so the event flag
  # and this guarantee are not fiber-path-specific.
  it "never drops a frame with a cannon-fire event under the stepwise engine either" do
    shooter = "main(\"S\") do\n  while true\n    cannon(0, 5)\n    sleep\n  end\nend\n"
    f = B::Field.new([{"s", shooter}, {"i", IDLE}], seed: 1_u64, limit: 30_000_i64, max_frames: 2).run_stepwise
    impacts = f.frames.count { |fr| fr.missiles.any?(&.exploding) }
    impacts.should be >= 10
    f.frames.size.should be > 2
  end

  # A robot that dies has damage >= 100 in exactly one recorded frame's
  # worth of state (the death update): a downsample-only log could show
  # the robot alive right up to a frame long after it actually died.
  it "never drops the frame a robot dies in, however tight the frame budget" do
    counter = File.read("examples/counter.cr")
    target = File.read("examples/target.cr")
    f = B::Field.new([{"counter", counter}, {"target", target}], seed: 1_u64, limit: 200_000_i64, max_frames: 2).run
    dead_frame = f.frames.find { |fr| fr.robots.any? { |r| !r.active } }
    dead_frame.should_not be_nil
    f.frames.size.should be > 2
  end
end
