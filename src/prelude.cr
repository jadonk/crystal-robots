require "prelude"
require "random"
require "math"
require "./crystal-robots"

def rand(limit)
  r = Random.rand(limit)
  puts "rand #{limit} -> #{r}"
  r
end

def sqrt(number)
  r = Math.isqrt(number.abs)
  puts "sqrt #{number} -> #{r}"
  r
end

def sin(degree)
  r = f2i(Math.sin(d2r(degree)))
  puts "sin #{degree} -> #{r}"
  r
end

def cos(degree)
  r = f2i(Math.cos(d2r(degree)))
  puts "cos #{degree} -> #{r}"
  r
end

def tan(degree)
  r = f2i(Math.tan(d2r(degree)))
  puts "tan #{degree} -> #{r}"
  r
end

def atan(ratio)
  r = r2d(Math.atan(i2f(ratio)))
  puts "tan #{ratio} -> #{r}"
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

def drive(dest_x, dest_y)
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.drive(dest_x, dest_y)
end

def speed
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.speed
end

def loc_x
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.loc_x
end

def loc_y
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.loc_x
end

def main(name, &program)
  r = CrystalRobots::Robot.new name
  r.activate
  r.main do |r|
    program.call
  end
end
