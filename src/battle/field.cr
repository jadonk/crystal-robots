# The battlefield: a port of the CROBOTS physics (Tom Poindexter, 1985,
# GPL v2), from `motion.c`, `intrins.c` and the match loop in `main.c`.
#
# Units follow CROBOTS: the field is 1000 by 1000 meters, positions are
# kept in clicks (10 per meter), headings are degrees with 0 east and 90
# north, (0,0) is the lower-left corner. Robots are multi-tasked one
# instruction at a time; every MOTION_CYCLES instructions the robots and
# missiles move. Here an "instruction" is one interpreter step.
#
# Everything is deterministic for a given seed, so a match can be replayed
# by re-running it.
require "../compiler"

module CrystalRobots::Battle
  CLICK         =         10 # clicks per meter
  MAX_X         =       1000 # meters
  MAX_Y         =       1000
  MOTION_CYCLES =         15 # instructions between motion updates
  CYCLE_LIMIT   = 500000_i64
  ROBOT_SPEED   =          7 # clicks per motion cycle at speed 10
  TURN_SPEED    =         50 # fastest speed at which a robot can turn
  ACCEL         =         10 # speed change per motion cycle
  MIS_SPEED     =        500 # clicks per motion cycle
  MIS_RANGE     =        700 # meters
  MIS_ROBOT     =          2 # missiles in flight per robot
  RELOAD        =         15 # motion cycles before the cannon can fire again
  EXP_COUNT     =          5 # motion cycles an explosion is shown
  COLLISION     =          2 # damage for hitting a wall or a robot
  RES_LIMIT     =         10 # widest scan resolution
  RAD_DEG       =   57.29578

  # Explosion damage by distance in meters: {within, percent}.
  DAMAGE = [{5, 10}, {20, 5}, {40, 3}]

  # sin * 100000 for 0..90 degrees; CROBOTS avoids floating point here.
  TRIG_TBL = [
    0, 1745, 3489, 5233, 6975, 8715, 10452, 12186, 13917, 15643,
    17364, 19080, 20791, 22495, 24192, 25881, 27563, 29237, 30901, 32556,
    34202, 35836, 37460, 39073, 40673, 42261, 43837, 45399, 46947, 48480,
    50000, 51503, 52991, 54463, 55919, 57357, 58778, 60181, 61566, 62932,
    64278, 65605, 66913, 68199, 69465, 70710, 71933, 73135, 74314, 75470,
    76604, 77714, 78801, 79863, 80901, 81915, 82903, 83867, 84804, 85716,
    86602, 87461, 88294, 89100, 89879, 90630, 91354, 92050, 92718, 93358,
    93969, 94551, 95105, 95630, 96126, 96592, 97029, 97437, 97814, 98162,
    98480, 98768, 99026, 99254, 99452, 99619, 99756, 99862, 99939, 99984,
    100000,
  ]

  def self.lsin(deg : Int32) : Int32
    deg = deg % 360
    deg += 360 if deg < 0
    case deg
    when .< 91  then TRIG_TBL[deg]
    when .< 181 then TRIG_TBL[90 - (deg - 90)]
    when .< 271 then -TRIG_TBL[deg - 180]
    else             -TRIG_TBL[90 - (deg - 270)]
    end
  end

  def self.lcos(deg : Int32) : Int32
    deg = deg % 360
    deg += 360 if deg < 0
    case deg
    when .< 91  then TRIG_TBL[90 - deg]
    when .< 181 then -TRIG_TBL[deg - 90]
    when .< 271 then -TRIG_TBL[90 - (deg - 180)]
    else             TRIG_TBL[deg - 270]
    end
  end

  enum MissileStatus
    Avail
    Flying
    Exploding
  end

  class Missile
    property stat = MissileStatus::Avail
    property beg_x = 0, beg_y = 0, cur_x = 0, cur_y = 0
    property head = 0, count = 0, rang = 0, curr_dist = 0
  end

  # Snapshot types for the replay trace.
  record RobotState, name : String, x : Int32, y : Int32, heading : Int32, speed : Int32,
    damage : Int32, scan : Int32, active : Bool
  record MissileState, x : Int32, y : Int32, exploding : Bool
  record Frame, cycle : Int64, robots : Array(RobotState), missiles : Array(MissileState)

  # Raised inside a robot fiber to unwind it when the match is over.
  private class Aborted < Exception
  end

  # One robot: its CROBOTS state plus the interpreter running its program.
  # The interpreter runs in a fiber; `cycle` lets it execute exactly one
  # step and returns when the step is done, which gives CROBOTS-style
  # instruction-level multitasking with no shared mutable scheduling state.
  class Robot
    property name : String, source : String
    property active = false
    property x = 0, y = 0, org_x = 0, org_y = 0, range = 0
    property speed = 0, accel = 0, d_speed = 0
    property heading = 0, d_heading = 0
    property damage = 0, scan = 0, reload = 0
    getter missiles : Array(Missile)
    getter output = [] of String
    getter error : String? = nil
    getter cycles = 0_i64
    getter restarts = 0
    getter program : Compiler::Program? = nil

    MAX_OUTPUT = 200

    @go = Channel(Bool).new
    @done = Channel(Nil).new(1)
    @alive = false

    def initialize(@name : String, @source : String, @field : Field)
      @missiles = Array(Missile).new(MIS_ROBOT) { Missile.new }
    end

    def alive? : Bool
      @alive
    end

    # Parse the program and start its fiber, parked until the first cycle.
    def start : Nil
      begin
        @program = Compiler::Parser.new(@source).program
      rescue parse_error : Compiler::Parser::Error
        @error = parse_error.message
        @active = false
        return
      end
      @active = true
      @alive = true
      program = @program.not_nil!
      host = RobotHost.new(self, @field)
      spawn(name: "robot #{@name}") do
        begin
          raise Aborted.new unless @go.receive
          loop do
            interpreter = Compiler::Interpreter.new(program, host, Int32::MAX)
            interpreter.on_step = -> do
              @cycles += 1
              @done.send(nil)
              raise Aborted.new unless @go.receive
            end
            begin
              interpreter.run
            rescue err : Compiler::Interpreter::RuntimeError
              note("runtime error: #{err.message}")
            end
            # CROBOTS restarts `main` when it returns or fails
            @restarts += 1
            @cycles += 1
            @done.send(nil)
            raise Aborted.new unless @go.receive
          end
        rescue Aborted
        ensure
          @alive = false
          @done.send(nil)
        end
      end
    end

    # Run one instruction.
    def cycle : Nil
      return unless @alive
      @go.send(true)
      @done.receive
    end

    # Unwind the fiber.
    def stop : Nil
      return unless @alive
      @go.send(false)
      @done.receive
    end

    def note(line : String) : Nil
      @output << line if @output.size < MAX_OUTPUT
    end

    def state : RobotState
      RobotState.new(@name, @x, @y, @heading, @speed, @damage, @scan, @active)
    end
  end

  # The builtins as seen by one robot.
  class RobotHost < Compiler::Host
    def initialize(@robot : Robot, @field : Field)
    end

    def scan(degree : Int32, resolution : Int32) : Int32
      @field.scan(@robot, degree, resolution)
    end

    def cannon(degree : Int32, range : Int32) : Int32
      @field.cannon(@robot, degree, range)
    end

    def drive(degree : Int32, speed : Int32) : Int32
      @field.drive(@robot, degree, speed)
    end

    def damage : Int32
      @robot.damage
    end

    def speed : Int32
      @robot.speed
    end

    def loc_x : Int32
      @robot.x // CLICK
    end

    def loc_y : Int32
      @robot.y // CLICK
    end

    def sleep : Int32
      0
    end

    def rand(limit : Int32) : Int32
      @field.rand(limit)
    end

    def puts(value : Compiler::Value) : Nil
      @robot.note(value.to_s)
    end
  end

  class Field
    getter robots = [] of Robot
    getter frames = [] of Frame
    getter cycles = 0_i64
    getter seed : UInt64
    getter limit : Int64

    # `entries` are {name, source} pairs, at most four.
    def initialize(entries : Array({String, String}), @seed : UInt64 = 1_u64, @limit : Int64 = CYCLE_LIMIT, @max_frames : Int32 = 200)
      raise ArgumentError.new("at most 4 robots") if entries.size > 4
      @random = Random.new(@seed)
      entries.each { |(name, source)| @robots << Robot.new(name, source, self) }
    end

    def rand(limit : Int32) : Int32
      limit <= 0 ? 0 : @random.rand(limit)
    end

    def active : Array(Robot)
      @robots.select(&.active)
    end

    # The winner when exactly one robot is left, else nil (a draw or a limit).
    def winner : Robot?
      survivors = active
      survivors.size == 1 ? survivors[0] : nil
    end

    # Run the match to its end: one survivor or the cycle limit.
    def run : self
      @robots.each(&.start)
      rand_pos
      record(0)
      movement = MOTION_CYCLES
      c = 0_i64
      every = Math.max(1_i64, (@limit // MOTION_CYCLES) // @max_frames)
      updates = 0_i64
      while active.size > 1 && c < @limit
        @robots.each { |r| r.cycle if r.active }
        movement -= 1
        if movement == 0
          c += MOTION_CYCLES
          movement = MOTION_CYCLES
          move_robots
          move_missiles
          count_missiles
          updates += 1
          record(c) if updates % every == 0
        end
      end
      # let flying missiles land
      guard = 0
      while @robots.any? { |r| r.missiles.any? { |m| m.stat.flying? } } && guard < 100
        c += MOTION_CYCLES
        move_robots
        move_missiles
        count_missiles
        guard += 1
      end
      @cycles = c
      record(c)
      @robots.each(&.stop)
      self
    end

    # Place robot i at a position in meters (for specs and demos).
    def place(i : Int32, x_m : Int32, y_m : Int32) : Nil
      r = @robots[i]
      r.x = r.org_x = x_m * CLICK
      r.y = r.org_y = y_m * CLICK
      r.range = 0
    end

    private def record(c : Int64) : Nil
      missiles = [] of MissileState
      @robots.each do |r|
        r.missiles.each do |m|
          next if m.stat.avail?
          missiles << MissileState.new(m.cur_x, m.cur_y, m.stat.exploding?)
        end
      end
      @frames << Frame.new(c, @robots.map(&.state), missiles)
    end

    # CROBOTS rand_pos: one robot per quadrant.
    private def rand_pos : Nil
      quad = [false, false, false, false]
      @robots.each do |r|
        k = rand(4)
        if quad[k]
          while quad[k]
            k = (k + 1) % 4
          end
        end
        quad[k] = true
        r.x = r.org_x = rand(MAX_X * CLICK // 2) + (MAX_X * CLICK // 2) * (k % 2)
        r.y = r.org_y = rand(MAX_Y * CLICK // 2) + (MAX_Y * CLICK // 2) * (k < 2 ? 1 : 0)
      end
    end

    # CROBOTS move_robots.
    def move_robots : Nil
      @robots.each_with_index do |r, i|
        next unless r.active
        if r.damage >= 100
          r.damage = 100
          r.active = false
          next
        end
        r.reload -= 1 if r.reload > 0

        if r.speed != r.d_speed
          if r.speed > r.d_speed
            r.accel -= ACCEL
            if r.accel < r.d_speed
              r.speed = r.accel = r.d_speed
            else
              r.speed = r.accel
            end
          else
            r.accel += ACCEL
            if r.accel > r.d_speed
              r.speed = r.accel = r.d_speed
            else
              r.speed = r.accel
            end
          end
        end

        if r.heading != r.d_heading
          if r.speed <= TURN_SPEED
            r.heading = r.d_heading
            r.range = 0
            r.org_x = r.x
            r.org_y = r.y
          else
            r.d_speed = 0
          end
        end

        if r.speed > 0
          r.range += (r.speed // CLICK) * ROBOT_SPEED
          r.x = r.org_x + (Battle.lcos(r.heading).to_i64 * (r.range // CLICK) // 10000).to_i32
          r.y = r.org_y + (Battle.lsin(r.heading).to_i64 * (r.range // CLICK) // 10000).to_i32

          @robots.each_with_index do |other, n|
            next if !other.active || n == i
            if (r.x - other.x).abs < CLICK && (r.y - other.y).abs < CLICK
              r.speed = 0
              r.d_speed = 0
              r.damage += COLLISION
              other.speed = 0
              other.d_speed = 0
              other.damage += COLLISION
            end
          end

          if r.x < 0
            r.x = 0
            r.speed = r.d_speed = 0
            r.damage += COLLISION
          elsif r.x > MAX_X * CLICK
            r.x = MAX_X * CLICK - 1
            r.speed = r.d_speed = 0
            r.damage += COLLISION
          end
          if r.y < 0
            r.y = 0
            r.speed = r.d_speed = 0
            r.damage += COLLISION
          elsif r.y > MAX_Y * CLICK
            r.y = MAX_Y * CLICK - 1
            r.speed = r.d_speed = 0
            r.damage += COLLISION
          end
        end
      end
    end

    # CROBOTS move_miss.
    def move_missiles : Nil
      @robots.each do |r|
        if r.damage >= 100
          r.damage = 100
          r.active = false
        end
        r.missiles.each do |m|
          next unless m.stat.flying?
          m.curr_dist += MIS_SPEED
          m.curr_dist = m.rang if m.curr_dist > m.rang
          x = m.beg_x + (Battle.lcos(m.head).to_i64 * (m.curr_dist // CLICK) // 10000).to_i32
          y = m.beg_y + (Battle.lsin(m.head).to_i64 * (m.curr_dist // CLICK) // 10000).to_i32
          m.cur_x = x
          m.cur_y = y
          if x < 0
            m.stat = MissileStatus::Exploding
            x = 1
          end
          if x >= MAX_X * CLICK
            m.stat = MissileStatus::Exploding
            x = MAX_X * CLICK - 1
          end
          if y < 0
            m.stat = MissileStatus::Exploding
            y = 1
          end
          if y > MAX_Y * CLICK
            m.stat = MissileStatus::Exploding
            y = MAX_Y * CLICK - 1
          end
          m.stat = MissileStatus::Exploding if m.curr_dist == m.rang
          next unless m.stat.exploding?
          @robots.each do |target|
            next unless target.active
            dx = (target.x - m.cur_x) // CLICK
            dy = (target.y - m.cur_y) // CLICK
            d = Math.sqrt((dx.to_f64 * dx) + (dy.to_f64 * dy)).to_i32
            DAMAGE.each do |(within, percent)|
              if d < within
                target.damage += percent
                break
              end
            end
            if target.damage >= 100
              target.damage = 100
              target.active = false
            end
          end
        end
      end
    end

    # Explosions are shown for EXP_COUNT motion cycles, then the missile
    # is available again.
    def count_missiles : Nil
      @robots.each do |r|
        r.missiles.each do |m|
          next unless m.stat.exploding?
          m.count -= 1
          m.stat = MissileStatus::Avail if m.count <= 0
        end
      end
    end

    # CROBOTS c_scan: distance in meters to the closest other robot within
    # +/- resolution degrees of `degree`, or 0.
    def scan(robot : Robot, degree : Int32, res : Int32) : Int32
      res = res.clamp(0, RES_LIMIT)
      degree = degree.abs % 360
      robot.scan = degree
      closest = 0
      @robots.each do |other|
        next if other.same?(robot) || !other.active
        x = ((robot.x // CLICK) - (other.x // CLICK)).to_f64
        y = ((robot.y // CLICK) - (other.y // CLICK)).to_f64
        d = if (x + 0.5).to_i32 == 0
              other.y > robot.y ? 90 : 270
            elsif other.y < robot.y
              other.x > robot.x ? (360.0 + RAD_DEG * Math.atan(y / x)).to_i32 : (180.0 + RAD_DEG * Math.atan(y / x)).to_i32
            else
              other.x > robot.x ? (RAD_DEG * Math.atan(y / x)).to_i32 : (180.0 + RAD_DEG * Math.atan(y / x)).to_i32
            end
        if degree > res && degree < 360 - res
          dd = degree
          d1 = d - res
          d2 = d + res
        else
          # CROBOTS shifts both angles by 180 here but never normalizes them,
          # so a scan at 359 could not see a robot at 0 even though the manual
          # promises wrap-around. Both are normalized here on purpose.
          dd = (degree + 180) % 360
          center = (d + 180) % 360
          d1 = center - res
          d2 = center + res
        end
        if dd >= d1 && dd <= d2
          distance = Math.sqrt(x * x + y * y).to_i32
          closest = distance if distance < closest || closest == 0
        end
      end
      closest
    end

    # CROBOTS c_cannon: 1 when a missile was fired, 0 when reloading or
    # both missiles are in the air.
    def cannon(robot : Robot, degree : Int32, distance : Int32) : Int32
      return 1 if distance < 0
      distance = MIS_RANGE if distance > MIS_RANGE
      degree = degree.abs % 360
      return 0 if robot.reload > 0
      robot.missiles.each do |m|
        next unless m.stat.avail?
        robot.reload = RELOAD
        m.stat = MissileStatus::Flying
        m.beg_x = m.cur_x = robot.x
        m.beg_y = m.cur_y = robot.y
        m.head = degree
        m.rang = distance * CLICK
        m.curr_dist = 0
        m.count = EXP_COUNT
        return 1
      end
      0
    end

    # CROBOTS c_drive.
    def drive(robot : Robot, degree : Int32, speed : Int32) : Int32
      robot.d_heading = degree.abs % 360
      robot.d_speed = speed.clamp(0, 100)
      1
    end
  end
end
