require "./channel"
require "../battle/field"

module CrystalRobots::Badge
  # Wires a live `Battle::Field` to the badge-launcher wire contract: on
  # the contract's cadence, publishes `status.json` from the field's
  # robots and applies whatever command is waiting in `command.json`.
  #
  # CROBOTS robots run their own compiled program rather than taking a
  # joystick, so commands map onto the closest thing the engine already
  # has: `estop`/`resume` toggle `Robot#active` (the field simply stops
  # cycling an inactive robot, and its fiber stays parked mid-run, ready
  # to resume), `move` nudges position, `calibrate` clears motion state.
  # `select_robot` and `ping` are informational only -- the next status
  # tick already carries a bumped `seq`.
  class Session
    DEFAULT_TICK = 200.milliseconds # the contract's 5 Hz status cadence

    def initialize(@field : Battle::Field,
                   @status_writer : StatusWriter = StatusWriter.new,
                   @command_reader : CommandReader = CommandReader.new,
                   @tick_interval : Time::Span = DEFAULT_TICK)
      @estopped = Set(String).new
      @last_tick_at = Time.monotonic - @tick_interval
    end

    # Ids are stable and index-based ("robot-1", ...), matching the
    # contract's example, independent of possibly-duplicate robot names.
    def robot_id(index : Int32) : String
      "robot-#{index + 1}"
    end

    def robot_for(id : String) : Battle::Robot?
      @field.robots.each_with_index { |r, i| return r if robot_id(i) == id }
      nil
    end

    def robot_status(index : Int32, robot : Battle::Robot) : RobotStatus
      id = robot_id(index)
      state = if robot.error
                "ERROR"
              elsif @estopped.includes?(id)
                "ESTOP"
              elsif robot.active
                "RUNNING"
              else
                "IDLE"
              end
      {
        id:        id,
        name:      robot.name,
        connected: robot.alive?,
        # No physical battery on a simulated robot; damage taken is the
        # closest existing signal, so battery_pct reports health remaining.
        battery_pct: (100 - robot.damage).clamp(0, 100),
        state:       state,
        position:    {
          x:           robot.x / Battle::CLICK.to_f64,
          y:           robot.y / Battle::CLICK.to_f64,
          heading_deg: robot.heading.to_f64,
        },
        task:       robot.active ? "battle" : (robot.error ? "stopped" : "idle"),
        error_text: robot.error || "",
      }
    end

    def mode : String
      robots = @field.robots
      !robots.empty? && @estopped.size >= robots.size ? "PAUSED" : "LIVE"
    end

    def publish_status : Nil
      robots = @field.robots.map_with_index { |r, i| robot_status(i, r) }
      @status_writer.write(mode, robots)
    end

    def apply_pending_command : Nil
      cmd = @command_reader.read
      apply(cmd) if cmd
    end

    # Runs the match to completion, publishing status and applying
    # commands on the contract's cadence until the field is done.
    #
    # Driven from `Field#run`'s own per-motion-update hook rather than a
    # concurrently spawned fiber: the interpreter drives motion updates by
    # handing control back and forth between robot fibers with no real
    # waiting in between, so a fiber ticking on a wall-clock `sleep`
    # instead can be starved for the entire match (the scheduler has no
    # reason to prefer a sleeping fiber over one that is always ready).
    # Ticking from inside the loop that is already running removes the
    # need to interleave with it at all; wall-clock rate limiting inside
    # `tick` still gives the contract's 5 Hz cadence for file writes.
    def run_until_done : Nil
      publish_status
      @field.run(->(_field : Battle::Field) { tick })
      publish_status
    end

    private def tick : Nil
      now = Time.monotonic
      return if now - @last_tick_at < @tick_interval
      @last_tick_at = now
      apply_pending_command
      publish_status
    end

    private def apply(cmd : Command) : Nil
      case cmd.command
      when "estop"
        each_target(cmd.target) { |i, r| r.active = false; @estopped << robot_id(i) }
      when "resume"
        each_target(cmd.target) { |i, r| r.active = true unless r.error; @estopped.delete(robot_id(i)) }
      when "move"
        if (target = cmd.target) && (r = robot_for(target))
          dx = cmd.args["dx"]?.try(&.as_f?) || 0.0
          dy = cmd.args["dy"]?.try(&.as_f?) || 0.0
          r.x += (dx * Battle::CLICK).round.to_i32
          r.y += (dy * Battle::CLICK).round.to_i32
        end
      when "calibrate"
        if (target = cmd.target) && (r = robot_for(target))
          r.speed = 0
          r.d_speed = 0
          r.accel = 0
        end
      when "select_robot", "ping"
        # informational / liveness only, no field state to change
      end
    end

    private def each_target(target : String?, & : Int32, Battle::Robot ->) : Nil
      @field.robots.each_with_index do |r, i|
        yield i, r if target.nil? || robot_id(i) == target
      end
    end
  end
end
