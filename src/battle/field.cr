# The CROBOTS battlefield, ported from the original C source
# (tpoindex/crobots, `motion.c`/`intrins.c`/`main.c`), not from memory --
# see the README for where that source lives. This commit is robot
# motion only: speed moderated by acceleration, heading changes allowed
# only below `TURN_SPEED`, position updated from heading and distance
# traveled, and collisions with another robot or a wall. Missiles and the
# scanner (`move_miss`, `c_scan`) are later commits.
module CrystalRobots::Battle
  MAX_X = 1000 # meters
  MAX_Y = 1000 # meters
  CLICK =   10 # clicks per meter; every position below is in clicks

  ROBOT_SPEED =  7 # multiplicative speed factor
  TURN_SPEED  = 50 # maximum speed for a heading change
  ACCEL       = 10 # acceleration per motion cycle

  COLLISION = 2 # damage percent for hitting a robot or a wall

  # Fixed-point sin/cos, scaled by 100000 like CROBOTS's own lookup
  # table (`trig_tbl` in motion.c) and its `sin`/`cos` builtins, so a
  # robot's own trig calls and the field's motion math agree on what a
  # heading means.
  SCALE = 100_000_i64

  def self.lsin(deg : Int32) : Int64
    (Math.sin(deg.to_f * Math::PI / 180) * SCALE).round.to_i64
  end

  def self.lcos(deg : Int32) : Int64
    (Math.cos(deg.to_f * Math::PI / 180) * SCALE).round.to_i64
  end

  class Robot
    getter name : String
    property status : Symbol      # :active | :dead
    property x = 0, y = 0         # current location, clicks
    property org_x = 0, org_y = 0 # location the current heading started from
    property range = 0            # distance traveled on this heading
    property speed = 0            # current speed, 0..100
    property accel = 0            # acceleration lag toward d_speed
    property d_speed = 0          # desired speed
    property heading = 0          # current heading, 0..359
    property d_heading = 0        # desired heading
    property damage = 0           # percent
    property scan = 0             # last scan direction, for display
    property reload = 0           # cycles until the cannon can fire again

    def initialize(@name : String)
      @status = :active
    end

    def alive? : Bool
      @status == :active
    end
  end

  # 1000x1000 meter field; robots given at construction start in
  # separate quadrants (`rand_pos` in main.c). A seed makes a match
  # reproducible.
  class Field
    getter robots : Array(Robot)

    def initialize(names : Array(String), seed : Int32? = nil)
      raise ArgumentError.new("at most 4 robots") if names.size > 4
      @rng = seed ? Random.new(seed) : Random.new
      @robots = names.map { |n| Robot.new(n) }
      place_robots
    end

    # rand_pos (main.c): each robot gets its own quadrant, then a random
    # position within it.
    private def place_robots : Nil
      quadrants = [0, 1, 2, 3]
      half_x = MAX_X * CLICK // 2
      half_y = MAX_Y * CLICK // 2
      @robots.each do |r|
        k = quadrants.delete_at(@rng.rand(quadrants.size))
        r.org_x = r.x = @rng.rand(half_x) + half_x * (k % 2)
        r.org_y = r.y = @rng.rand(half_y) + half_y * (k < 2 ? 1 : 0)
      end
    end

    # move_robots (motion.c), minus the missile-related parts (later
    # commits): moderate speed by acceleration, allow a heading change
    # only at or below TURN_SPEED, advance position, and check for
    # collisions with another robot or a wall.
    def move_robots : Nil
      @robots.each_with_index do |r, i|
        next unless r.alive?

        if r.damage >= 100
          r.damage = 100
          r.status = :dead
          next
        end

        r.reload -= 1 if r.reload > 0

        if r.speed != r.d_speed
          if r.speed > r.d_speed # slowing
            r.accel -= ACCEL
            if r.accel < r.d_speed
              r.speed = r.accel = r.d_speed
            else
              r.speed = r.accel
            end
          else # accelerating
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

        next unless r.speed > 0
        r.range += (r.speed // CLICK) * ROBOT_SPEED
        # Truncating division (`tdiv`), not floored (`//`): this mirrors
        # C's `long / long`, which matters once cos/sin go negative.
        r.x = (r.org_x + (lcos(r.heading) * (r.range // CLICK)).tdiv(SCALE)).to_i32
        r.y = (r.org_y + (lsin(r.heading) * (r.range // CLICK)).tdiv(SCALE)).to_i32

        check_collisions(i)
        check_walls(r)
      end
    end

    private def lsin(deg : Int32) : Int64
      Battle.lsin(deg)
    end

    private def lcos(deg : Int32) : Int64
      Battle.lcos(deg)
    end

    # A moving robot within one click of another (in both x and y) hits
    # it: both stop and take collision damage.
    private def check_collisions(i : Int32) : Nil
      r = @robots[i]
      @robots.each_with_index do |other, n|
        next if n == i || !other.alive?
        next unless (r.x - other.x).abs < CLICK && (r.y - other.y).abs < CLICK
        stop_with_damage(r)
        stop_with_damage(other)
      end
    end

    private def check_walls(r : Robot) : Nil
      if r.x < 0
        r.x = 0
        stop_with_damage(r)
      elsif r.x > MAX_X * CLICK
        r.x = (MAX_X * CLICK) - 1
        stop_with_damage(r)
      end
      if r.y < 0
        r.y = 0
        stop_with_damage(r)
      elsif r.y > MAX_Y * CLICK
        r.y = (MAX_Y * CLICK) - 1
        stop_with_damage(r)
      end
    end

    private def stop_with_damage(r : Robot) : Nil
      r.speed = 0
      r.d_speed = 0
      r.damage += COLLISION
    end
  end
end
