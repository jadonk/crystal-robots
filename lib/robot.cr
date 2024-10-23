# Simulate robot intrinsic functions
#
# http://tpoindex.github.io/crobots/docs/crobots_manual.html#8
#
# This is to enable native compilation of robots for syntax checking

require "math"
require "random"

# Eventually, there will be CPU cycle counting, but for now, I'll just
# count the number of calls and throw an exception when it is reached

class Robot
  MAX_CALLS = 100
  @calls : UInt32
  @loc_x : Int32
  @loc_y : Int32
  @damage : Int32
  @speed : Int32

  def initialize
    @calls = 0
    @loc_x = rand(1000)
    @loc_y = rand(1000)
    @damage = 0
    @speed = 0
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
    debug "loc_x -> #{@loc_x}"
    @loc_x
  end

  def loc_y
    debug "loc_y -> #{@loc_y}"
    @loc_y
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
