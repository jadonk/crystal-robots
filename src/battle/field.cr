# The CROBOTS battlefield, ported from the original C source
# (tpoindex/crobots, `motion.c`/`intrins.c`/`main.c`), not from memory --
# see the README for where that source lives. This commit adds missiles:
# firing (`c_cannon`), flight and explosion (`move_miss`), and the
# explosion-radius damage table. The scanner (`c_scan`) is a later
# commit; nothing here is wired to a running robot program yet -- `Field`
# is exercised directly.
module CrystalRobots::Battle
  MAX_X = 1000 # meters
  MAX_Y = 1000 # meters
  CLICK =   10 # clicks per meter; every position below is in clicks

  ROBOT_SPEED =  7 # multiplicative speed factor
  TURN_SPEED  = 50 # maximum speed for a heading change
  ACCEL       = 10 # acceleration per motion cycle

  COLLISION = 2 # damage percent for hitting a robot or a wall

  MIS_SPEED = 500 # how far a missile flies in one motion cycle, in clicks
  MIS_RANGE = 700 # maximum cannon range, meters
  MIS_ROBOT =   2 # missiles a robot may have in the air at once
  RELOAD    =  15 # motion cycles between shots
  EXP_COUNT =   5 # motion cycles an exploded missile lingers before reload

  # Explosion damage by distance from the blast, closest first; a robot
  # beyond FAR_RANGE takes no damage. (exp_dam in motion.c.)
  DIRECT_RANGE =  5
  DIRECT_HIT   = 10
  NEAR_RANGE   = 20
  NEAR_HIT     =  5
  FAR_RANGE    = 40
  FAR_HIT      =  3

  RES_LIMIT = 10 # scan resolution limit, degrees

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

  enum MissileStatus
    Avail
    Flying
    Exploding
  end

  class Missile
    property status : MissileStatus = MissileStatus::Avail
    property beg_x = 0, beg_y = 0 # firing position, clicks
    property cur_x = 0, cur_y = 0 # current position, clicks
    property heading = 0          # 0..359
    property count = 0            # motion cycles left showing EXPLODING
    property range = 0            # target range, clicks
    property curr_dist = 0        # distance flown so far, clicks
  end

  # 1000x1000 meter field; robots given at construction start in
  # separate quadrants (`rand_pos` in main.c). A seed makes a match
  # reproducible.
  class Field
    getter robots : Array(Robot)
    getter missiles : Array(Array(Missile))

    def initialize(names : Array(String), seed : Int32? = nil)
      raise ArgumentError.new("at most 4 robots") if names.size > 4
      @rng = seed ? Random.new(seed) : Random.new
      @robots = names.map { |n| Robot.new(n) }
      @missiles = @robots.map { Array.new(MIS_ROBOT) { Missile.new } }
      place_robots
    end

    # c_rand (intrins.c): a random number in 0...limit, from this match's
    # own seeded RNG so a match replays identically.
    def rand(limit : Int32) : Int32
      limit <= 0 ? 0 : @rng.rand(limit)
    end

    # c_drive (intrins.c): set the desired heading and speed; move_robots
    # moderates the actual change by acceleration and the turn-speed limit.
    def drive(i : Int32, degree : Int32, speed : Int32) : Nil
      r = @robots[i]
      r.d_speed = speed.clamp(0, 100)
      degree = degree.abs
      degree %= 360 if degree >= 360
      r.d_heading = degree
    end

    # c_scan (intrins.c): the closest other robot within `resolution`
    # degrees of `degree`, or 0 for nothing. Bearings are found with
    # atan, not atan2, and the quadrant worked out by hand exactly as
    # intrins.c does, since that is what a ratio-based `atan` call from a
    # robot's own source (rabbit.cr, sniper.cr) already assumes.
    def scan(i : Int32, degree : Int32, resolution : Int32) : Int32
      me = @robots[i]
      res = resolution.clamp(0, RES_LIMIT)
      deg = degree.abs
      deg %= 360 if deg >= 360
      me.scan = deg

      closest = nil
      @robots.each_with_index do |other, n|
        next if n == i || !other.alive?
        x = (me.x // CLICK) - (other.x // CLICK) # meters, me - other
        y = (me.y // CLICK) - (other.y // CLICK)

        d = if (x + 0.5).to_i32 == 0
              other.y > me.y ? 90 : 270
            else
              base = (Math.atan(y.to_f / x.to_f) * 180.0 / Math::PI)
              if other.y < me.y
                (other.x > me.x ? 360.0 + base : 180.0 + base).to_i32
              else
                (other.x > me.x ? base : 180.0 + base).to_i32
              end
            end

        if deg > res && deg < 360 - res
          dd, d1, d2 = deg, d - res, d + res
        else
          dd, d1, d2 = deg + 180, 180 + d - res, 180 + d + res
        end
        next unless dd >= d1 && dd <= d2

        distance = Math.sqrt((x*x + y*y).to_f64)
        closest = distance if closest.nil? || distance < closest
      end
      closest ? closest.to_i32 : 0
    end

    private def lsin(deg : Int32) : Int64
      Battle.lsin(deg)
    end

    private def lcos(deg : Int32) : Int64
      Battle.lcos(deg)
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

    # c_cannon (intrins.c): fire from robot `i` if its cannon is not
    # reloading and it has a missile available. Faithfully reproduces one
    # CROBOTS quirk: a negative distance reports success (returns `true`)
    # without actually firing anything.
    def fire_missile(i : Int32, degree : Int32, distance : Int32) : Bool
      distance = MIS_RANGE if distance > MIS_RANGE
      return true if distance < 0
      degree = degree.abs
      degree %= 360 if degree >= 360

      r = @robots[i]
      return false if r.reload > 0
      slot = @missiles[i].find(&.status.avail?)
      return false unless slot

      r.reload = RELOAD
      slot.status = MissileStatus::Flying
      slot.beg_x = slot.cur_x = r.x
      slot.beg_y = slot.cur_y = r.y
      slot.heading = degree
      slot.range = distance * CLICK
      slot.curr_dist = 0
      slot.count = EXP_COUNT
      true
    end

    # move_miss (motion.c), plus count_miss (display.c) folded in: every
    # flying missile advances toward its target range or a wall, exploding
    # (and damaging nearby robots, once) when it reaches either; an
    # exploded missile becomes available again after EXP_COUNT cycles.
    def move_missiles : Nil
      @missiles.each do |robot_missiles|
        robot_missiles.each do |m|
          case m.status
          when .flying?
            advance_missile(m)
          when .exploding?
            if m.count <= 0
              m.status = MissileStatus::Avail
            else
              m.count -= 1
            end
          else
            # available: nothing to do
          end
        end
      end
    end

    private def advance_missile(m : Missile) : Nil
      m.curr_dist += MIS_SPEED
      m.curr_dist = m.range if m.curr_dist > m.range

      x = (m.beg_x + (lcos(m.heading) * (m.curr_dist // CLICK)).tdiv(SCALE)).to_i32
      y = (m.beg_y + (lsin(m.heading) * (m.curr_dist // CLICK)).tdiv(SCALE)).to_i32

      if x < 0
        m.status = MissileStatus::Exploding
        x = 1
      elsif x >= MAX_X * CLICK
        m.status = MissileStatus::Exploding
        x = (MAX_X * CLICK) - 1
      end
      if y < 0
        m.status = MissileStatus::Exploding
        y = 1
      elsif y > MAX_Y * CLICK
        m.status = MissileStatus::Exploding
        y = (MAX_Y * CLICK) - 1
      end

      m.cur_x = x
      m.cur_y = y
      m.status = MissileStatus::Exploding if m.curr_dist == m.range

      apply_explosion_damage(m) if m.status.exploding?
    end

    private def apply_explosion_damage(m : Missile) : Nil
      @robots.each do |target|
        next unless target.alive?
        dx = (target.x - m.cur_x) // CLICK
        dy = (target.y - m.cur_y) // CLICK
        d = Math.sqrt((dx*dx + dy*dy).to_f64).to_i32

        dmg = if d < DIRECT_RANGE
                DIRECT_HIT
              elsif d < NEAR_RANGE
                NEAR_HIT
              elsif d < FAR_RANGE
                FAR_HIT
              end
        next unless dmg
        target.damage += dmg
        if target.damage >= 100
          target.damage = 100
          target.status = :dead
        end
      end
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
