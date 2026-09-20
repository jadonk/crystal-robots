require "json"

# The local status/command interface between this crystal-robots process
# and badge-launcher, as defined by badge-launcher's
# `docs/crystal-robots-wire-contract.md` (crystal-robots ticket 27a70ff3ed,
# badge-launcher ticket 500ed41616). Two flat JSON files on disk, modeled
# on badge-launcher's existing BadgeSnake `STATE_PATH`/`COMMAND_PATH`
# pattern: crystal-robots writes `status.json` at 5 Hz, the badge writes
# `command.json` once per user action. Both sides treat that document as
# the source of truth; this module mirrors it field for field, and does
# not extend or reinterpret it.
module CrystalRobots::Badge
  SCHEMA_VERSION = 1

  # The six-command vocabulary the contract defines. Anything else is not
  # a valid command and `CommandReader` ignores it.
  COMMANDS = %w(estop resume select_robot move calibrate ping)

  # `CRYSTAL_ROBOTS_STATE_DIR`, or the individual path overrides, mirror
  # badge-launcher's `BADGESNAKE_STATE_DIR` convention.
  def self.state_dir : String
    ENV["CRYSTAL_ROBOTS_STATE_DIR"]? || "/tmp/crystal-robots"
  end

  def self.status_path : String
    ENV["CRYSTAL_ROBOTS_STATUS_PATH"]? || File.join(state_dir, "status.json")
  end

  def self.command_path : String
    ENV["CRYSTAL_ROBOTS_COMMAND_PATH"]? || File.join(state_dir, "command.json")
  end

  alias RobotStatus = NamedTuple(
    id: String,
    name: String,
    connected: Bool,
    battery_pct: Int32,
    state: String,
    position: NamedTuple(x: Float64, y: Float64, heading_deg: Float64),
    task: String,
    error_text: String)

  # One command read from `command.json`. `args` stays a raw `JSON::Any`
  # since its shape depends on `command` (e.g. `move`'s `dx`/`dy`).
  record Command, seq : Int32, command : String, target : String?, args : JSON::Any

  # Writes `status.json`, crystal-robots' half of the contract. `seq`
  # increments on every write, including an unchanged snapshot, so the
  # badge can tell a live host from a stalled one by watching `seq` /
  # `generated_at_ms` stop advancing.
  class StatusWriter
    def initialize(@path : String = CrystalRobots::Badge.status_path)
      @seq = 0
    end

    getter seq

    def write(mode : String, robots : Array(RobotStatus), event_text : String = "", banner_text : String = "") : Nil
      @seq += 1
      Dir.mkdir_p(File.dirname(@path))
      body = {
        schema_version:  SCHEMA_VERSION,
        generated_at_ms: Time.utc.to_unix_ms,
        seq:             @seq,
        mode:            mode,
        robots:          robots,
        event_text:      event_text,
        banner_text:     banner_text,
      }.to_json
      # Write-then-rename so the badge never reads a half-written file.
      tmp_path = "#{@path}.tmp"
      File.write(tmp_path, body)
      File.rename(tmp_path, @path)
    end
  end

  # Reads `command.json`, the badge's half of the contract. `read` returns
  # a given command at most once: a re-read with an unchanged `seq` is
  # "already consumed", per the contract's idempotency note, and a
  # missing, unreadable, or malformed file is "no command yet".
  class CommandReader
    def initialize(@path : String = CrystalRobots::Badge.command_path)
      @last_seq = 0
    end

    def read : Command?
      return nil unless File.exists?(@path)
      parsed = JSON.parse(File.read(@path))
      seq = parsed["seq"]?.try(&.as_i?)
      command = parsed["command"]?.try(&.as_s?)
      return nil unless seq && command
      return nil if seq <= @last_seq
      return nil unless COMMANDS.includes?(command)
      target = parsed["target"]?.try(&.as_s?)
      args = parsed["args"]? || JSON::Any.new({} of String => JSON::Any)
      @last_seq = seq
      Command.new(seq, command, target, args)
    rescue JSON::ParseException
      nil
    end
  end
end
