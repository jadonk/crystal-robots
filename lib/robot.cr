# Simulate robot intrinsic functions
#
# http://tpoindex.github.io/crobots/docs/crobots_manual.html#8
#
# This is to enable native compilation of robots for syntax checking

require "math"
require "random"
require "fiber"

# I'm trying to figure out how to interrupt the robot flow at some
# interval. It will never match the WASM interpreter cycles, but I
# hope I can make each robot yield to let another robot run.
#
# By not forcing robots to put their code inside a method, I'm
# having a bit of a hard time figuring out if I can manipulate the
# remaining code within the file

class Missile
  MIS_SPEED = 500       # how far in one motion cycle (in clicks)
  MIS_RANGE = 700       # maximum missile range
  MIS_ROBOT = 2         # number of active missiles per robot
  AVAIL = 0             # missile available for use
  FLYING = 1            # missile in air
  EXPLODING = 2         # missile exploding on ground
  RELOAD = 15           # motion cycles before reload
  EXP_COUNT = 5         # motion cycles for exploding missile

  def initialize
    @stat = AVAIL       # missile status
    @beg_x = 0          # beginning x * 100
    @beg_y = 0          # beginning y * 100
    @cur_x = 0          # current x * 100
    @cur_y = 0          # current y * 100
    @last_xx = -1       # last plotted x
    @last_yy = -1       # last plotted y
    @head = 0           # heading, 0 - 359
    @count = 0          # cycle count for exploding missiles
    @rang = 0           # range of missile
    @curr_dist = 0      # current distance from origin * 100
  end
end

class Robot
  @@num_robots = 0
  @@robots = [] of Robot
  MAX_CALLS = 100
  MAXROBOTS = 4                # maximum number of robots
  MOTION_CYCLES = 15           # number of cycles before motion update
  ROBOT_SPEED = 7              # multiplicative speed factor
  TURN_SPEED = 50              # maximum speed for direction change
  ACCEL = 10                   # acceleration per motion cycle
  @i : Int32

  def initialize(name : String)
    @name = "#{name}"
    @status = 0
    @calls = 0
    @x = 0
    @y = 0
    @org_x = 0
    @org_y = 0
    @range = 0
    @last_x = -1
    @last_y = -1
    @speed = 0
    @last_speed = -1
    @accel = 0
    @d_speed = 0
    @damage = 0
    @last_damage = -1
    @scan = 0
    @last_scan = -1
    @reload = 0
    @i = @@num_robots
    @@num_robots += 1
    if @@num_robots > MAXROBOTS
      raise "Too many robots!"
    end
  end

  def main(&program : Robot -> Nil)
    @@robots << self
    @program = program
    run
  end

  def run
    if program = @program
      puts "Running robot #{@i}, aka '#{@name}'"
      begin
        program.call(self)
      rescue ex
        puts "Stopping robot #{@i}, aka #{@name}: #{ex.message}"
      end
    end
  end

  private def debug(s)
    @calls += 1
    puts "#{@calls}: #{s}"
    if @calls >= MAX_CALLS
      raise "Maximum number of calls reached"
    end
  end

  def scan(degree, resolution)
    debug "scan #{degree} #{resolution}"
    0
  end

  def cannon(degree, range)
    r = true
    debug "cannon #{degree} #{range} -> #{r}"
    r
  end

  def drive(degree, speed)
    debug "drive #{degree} #{speed}"
  end

  def damage
    debug "damage -> #{@damage}"
    @damage
  end

  def speed
    debug "speed -> #{speed}"
    @speed
  end

  def loc_x
    r = @x // 100
    debug "loc_x -> #{r}"
    r
  end

  def loc_y
    r = @y // 100
    debug "loc_y -> #{r}"
    r
  end
end

private def debug(s)
  puts "other: #{s}"
end

def rand(limit)
  r = Random.rand(limit)
  debug "rand #{limit} -> #{r}"
  r
end

def sqrt(number)
  r = Math.isqrt(number.abs)
  debug "sqrt #{number} -> #{r}"
  r
end

def sin(degree)
  r = f2i(Math.sin(d2r(degree)))
  debug "sin #{degree} -> #{r}"
  r
end

def cos(degree)
  r = f2i(Math.cos(d2r(degree)))
  debug "cos #{degree} -> #{r}"
  r
end

def tan(degree)
  r = f2i(Math.tan(d2r(degree)))
  debug "tan #{degree} -> #{r}"
  r
end

def atan(ratio)
  r = r2d(Math.atan(i2f(ratio)))
  debug "tan #{ratio} -> #{r}"
  r
end

private def d2r(degree)
  degree * Math::PI / 180
end

private def r2d(radian)
  (radian * 180 / Math::PI).to_i32
end

private def f2i(x)
  (x*100000).to_i32
end

private def i2f(n)
  (n/100000).to_f32
end
