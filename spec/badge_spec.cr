require "./spec_helper"
require "../src/badge/session"
require "../src/battle/field"

alias Badge = CrystalRobots::Badge

private IDLE_SRC = "main(\"Idle\") do\n  while true\n    sleep\n  end\nend\n"

# A fresh scratch directory per example so specs never share, or race on,
# `status.json`/`command.json`.
private def badge_tmp_dir : String
  dir = File.tempname("crd-badge", nil)
  Dir.mkdir_p(dir)
  dir
end

private def field_of(*sources, limit = 3000_i64) : CrystalRobots::Battle::Field
  entries = sources.map_with_index { |src, i| {"r#{i}", src} }.to_a
  CrystalRobots::Battle::Field.new(entries, seed: 1_u64, limit: limit)
end

describe CrystalRobots::Badge do
  describe "StatusWriter" do
    it "writes status.json matching the wire contract's shape" do
      dir = badge_tmp_dir
      path = File.join(dir, "status.json")
      writer = Badge::StatusWriter.new(path)
      robot = {
        id: "robot-1", name: "ZEPTO-A", connected: true, battery_pct: 87,
        state: "RUNNING", position: {x: 1.2, y: 3.4, heading_deg: 90.0},
        task: "patrol", error_text: "",
      }
      writer.write("LIVE", [robot] of Badge::RobotStatus)

      fixture = JSON.parse(File.read("spec/fixtures/badge_status_example.json"))
      written = JSON.parse(File.read(path))

      written["schema_version"].should eq fixture["schema_version"]
      written["mode"].should eq fixture["mode"]
      written["seq"].as_i.should eq 1
      written["generated_at_ms"].as_i64.should be > 0
      written["event_text"].should eq ""
      written["banner_text"].should eq ""

      w_robot = written["robots"][0]
      f_robot = fixture["robots"][0]
      %w(id name connected battery_pct state task error_text).each do |field|
        w_robot[field].should eq f_robot[field]
      end
      w_robot["position"]["x"].as_f.should eq 1.2
      w_robot["position"]["y"].as_f.should eq 3.4
      w_robot["position"]["heading_deg"].as_f.should eq 90.0
    end

    it "bumps seq on every write, even an unchanged snapshot" do
      dir = badge_tmp_dir
      writer = Badge::StatusWriter.new(File.join(dir, "status.json"))
      writer.write("IDLE", [] of Badge::RobotStatus)
      writer.write("IDLE", [] of Badge::RobotStatus)
      writer.seq.should eq 2
    end
  end

  describe "CommandReader" do
    it "parses the wire contract's example command" do
      dir = badge_tmp_dir
      path = File.join(dir, "command.json")
      File.write(path, File.read("spec/fixtures/badge_command_example.json"))

      reader = Badge::CommandReader.new(path)
      cmd = reader.read
      cmd.should_not be_nil
      cmd = cmd.not_nil!
      cmd.seq.should eq 3
      cmd.command.should eq "estop"
      cmd.target.should eq "robot-1"
      cmd.args.as_h.should eq({} of String => JSON::Any)
    end

    it "returns nil for a missing file" do
      dir = badge_tmp_dir
      reader = Badge::CommandReader.new(File.join(dir, "command.json"))
      reader.read.should be_nil
    end

    it "is idempotent: a re-read with an unchanged seq returns nil" do
      dir = badge_tmp_dir
      path = File.join(dir, "command.json")
      File.write(path, %({"seq": 1, "command": "ping", "target": null, "args": {}}))
      reader = Badge::CommandReader.new(path)
      reader.read.should_not be_nil
      reader.read.should be_nil

      File.write(path, %({"seq": 2, "command": "ping", "target": null, "args": {}}))
      reader.read.should_not be_nil
    end

    it "ignores a command outside the six-command vocabulary" do
      dir = badge_tmp_dir
      path = File.join(dir, "command.json")
      File.write(path, %({"seq": 1, "command": "self_destruct", "target": null, "args": {}}))
      Badge::CommandReader.new(path).read.should be_nil
    end

    it "treats malformed JSON as no command yet" do
      dir = badge_tmp_dir
      path = File.join(dir, "command.json")
      File.write(path, "{not json")
      Badge::CommandReader.new(path).read.should be_nil
    end
  end

  describe "status/command round trip" do
    it "polls a status write and consumes the matching command in one pass" do
      dir = badge_tmp_dir
      status_path = File.join(dir, "status.json")
      command_path = File.join(dir, "command.json")

      status_writer = Badge::StatusWriter.new(status_path)
      status_writer.write("LIVE", [] of Badge::RobotStatus)

      File.write(command_path, %({"seq": 1, "command": "ping", "target": null, "args": {}}))
      command_reader = Badge::CommandReader.new(command_path)

      status = JSON.parse(File.read(status_path))
      status["seq"].as_i.should eq 1

      command = command_reader.read.not_nil!
      command.command.should eq "ping"

      status_writer.write("LIVE", [] of Badge::RobotStatus)
      JSON.parse(File.read(status_path))["seq"].as_i.should eq 2
    end
  end

  describe "Session" do
    it "publishes robot state from the field, id'd by battle order" do
      field = field_of(IDLE_SRC, IDLE_SRC)
      field.robots.each { |r| r.active = true }
      field.place(0, 100, 200)
      field.robots[0].heading = 45

      dir = badge_tmp_dir
      session = Badge::Session.new(field, Badge::StatusWriter.new(File.join(dir, "status.json")))
      session.publish_status

      status = JSON.parse(File.read(File.join(dir, "status.json")))
      first = status["robots"][0]
      first["id"].should eq "robot-1"
      first["name"].should eq "r0"
      first["state"].should eq "RUNNING"
      first["position"]["x"].as_f.should eq 100.0
      first["position"]["y"].as_f.should eq 200.0
      first["position"]["heading_deg"].as_f.should eq 45.0
    end

    it "applies an estop command to the targeted robot only" do
      field = field_of(IDLE_SRC, IDLE_SRC)
      field.robots.each { |r| r.active = true }

      dir = badge_tmp_dir
      command_path = File.join(dir, "command.json")
      File.write(command_path, %({"seq": 1, "command": "estop", "target": "robot-1", "args": {}}))

      session = Badge::Session.new(field,
        Badge::StatusWriter.new(File.join(dir, "status.json")),
        Badge::CommandReader.new(command_path))
      session.apply_pending_command

      field.robots[0].active.should be_false
      field.robots[1].active.should be_true

      session.publish_status
      status = JSON.parse(File.read(File.join(dir, "status.json")))
      status["robots"][0]["state"].should eq "ESTOP"
      status["robots"][1]["state"].should eq "RUNNING"
    end

    it "clears an estop on resume" do
      field = field_of(IDLE_SRC, IDLE_SRC)
      field.robots.each { |r| r.active = true }

      dir = badge_tmp_dir
      command_path = File.join(dir, "command.json")
      session = Badge::Session.new(field,
        Badge::StatusWriter.new(File.join(dir, "status.json")),
        Badge::CommandReader.new(command_path))

      File.write(command_path, %({"seq": 1, "command": "estop", "target": null, "args": {}}))
      session.apply_pending_command
      field.robots.each { |r| r.active.should be_false }

      File.write(command_path, %({"seq": 2, "command": "resume", "target": null, "args": {}}))
      session.apply_pending_command
      field.robots.each { |r| r.active.should be_true }
    end

    it "resume on an errored robot leaves it ERROR and status.json says so" do
      field = field_of("if x\n", IDLE_SRC) # a parse error fails robot-1 in Robot#start
      field.robots[0].start
      field.robots[1].active = true

      dir = badge_tmp_dir
      command_path = File.join(dir, "command.json")
      File.write(command_path, %({"seq": 1, "command": "resume", "target": "robot-1", "args": {}}))

      session = Badge::Session.new(field,
        Badge::StatusWriter.new(File.join(dir, "status.json")),
        Badge::CommandReader.new(command_path))
      session.apply_pending_command

      field.robots[0].active.should be_false
      field.robots[0].error.should_not be_nil

      session.publish_status
      status = JSON.parse(File.read(File.join(dir, "status.json")))
      status["robots"][0]["state"].should eq "ERROR"
      status["robots"][0]["error_text"].should_not eq ""
    end

    it "applies a move command's dx/dy to the targeted robot's position" do
      field = field_of(IDLE_SRC, IDLE_SRC)
      field.place(0, 100, 200)

      dir = badge_tmp_dir
      command_path = File.join(dir, "command.json")
      File.write(command_path, %({"seq": 1, "command": "move", "target": "robot-1", "args": {"dx": 5.0, "dy": -2.0}}))

      session = Badge::Session.new(field,
        Badge::StatusWriter.new(File.join(dir, "status.json")),
        Badge::CommandReader.new(command_path))
      session.apply_pending_command

      field.robots[0].x.should eq 1050 # 100m + 5m, in clicks (10/m)
      field.robots[0].y.should eq 1980 # 200m - 2m, in clicks
    end
  end
end
