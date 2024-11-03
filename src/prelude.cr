# Robot builtin methods
#
# http://tpoindex.github.io/crobots/docs/crobots_manual.html#8
#
# This is to enable native compilation of robots for syntax checking
#
# I'm trying to figure out how to interrupt the robot flow at some
# interval. It will never match the WASM interpreter cycles, but I
# hope I can make each robot yield to let another robot run.

require "prelude"
require "random"
require "math"
require "./crystal-robots"

# The `main` method provides an entry point for the `crystal-robots` virtual CPU for the robot.
#
# TODO: this needs a lot more description
#
# Examples:
#
# ```
# main("MyRobot") do
#   puts("Hello World!")
# end
# ```
def main(name, &program)
  r = CrystalRobots::Robot.new name
  r.main do |r|
    r.activate
    program.call
  end
end

# The `scan` method invokes the robot's scanner, at a specified degree and resolution. `scan` returns 0 if no robots are
# within the scan range or a positive integer representing the range to the closest robot. Degree should be within the
# range 0-359, otherwise degree is forced into 0-359 by a modulo 360 operation, and made positive if necessary. Resolution
# controls the scanner's sensing resolution, up to +/- 10 degrees.
#
# Examples:
#
# ```
# range = scan(45, 0)   # scan 45, with no variance
# range = scan(365, 10) # scans the range from 355 to 15
# ```
def scan(degree, resolution)
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.scan
end

# The `cannon` method fires a missile heading a specified range and direction. `cannon` returns 1 (true) if a missile was
# fired, or 0 (false) if the cannon is reloading. Degree is forced into the range 0-359 as in `scan`. Range can be 0-700,
# with greater ranges truncated to 700.
#
# Examples:
#
# ```
# degree = 45             # set a direction to scan
# range = scan(degree, 2) # scan for a target
# if range > 0            # if there is a target in range
#   cannon(degree, range) # fire a missle
# end
# ```
def cannon(degree, range)
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.scan
end

# The `drive` method activates the robot's drive mechanism, on a specified heading and speed. Degree is forced into the
# range 0-359 as in `scan`. Speed is expressed as a percent, with 100 as maximum. A speed of 0 disengages the drive.
# Changes in direction can be negotiated at speeds of less than 50 percent.
#
# Examples:
#
# ```
# drive(0, 100) # head due east, at maximum speed
# drive(90, 0)  # stop motion
# ```
def drive(dest_x, dest_y)
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.drive(dest_x, dest_y)
end

# The `damage` method returns the current amount of damage incurred. damage() takes no arguments, and returns the percent
# of damage, 0-99. (100 percent damage means the robot is completely disabled, thus no longer running!)
#
# Examples:
#
# ```
# d = damage # save current state
#
# ... # other instructions
#
# if d != damage   # compare current state to prior state
#   drive(90, 100) # robot has been hit, start moving
#   d = damage     # get current damage again
# end
# ```
def damage
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.damage
end

# The `speed` method returns the current speed of the robot. `speed` takes no arguments, and returns the percent of
# speed, 0-100. Note that `speed` may not always be the same as the last `drive`, because of acceleration and deceleration.
#
# Examples:
#
# ```
# drive(270, 100) # start drive, due south
#
# ... # other instructions
#
# if speed == 0   # check current speed
#   drive(90, 20) # ran into the south wall, or another robot
# end
# ```
def speed
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.speed
end

# The `loc_x` method returns the robot's current x axis location. `loc_x` takes no arguments, and returns 0-999. The
# `loc_y` method is similar to `loc_x`, but returns the current y axis position.
#
# Examples:
#
# ```
#   drive(180,50)      # start heading for west wall
#   while loc_x > 20 do
#                      # do nothing until we are close
#   end
#   drive(180,0)       # stop drive
# ```
def loc_x
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.loc_x
end

# See `loc_x`
def loc_y
  r = CrystalRobots::Robot.active_robot.not_nil!
  r.loc_x
end

# The `rand` method returns a random number between 0 and limit, up to 32767.
#
# Examples:
#
# ```
# degree = rand(360)      # pick a random starting point
# range = scan(degree, 0) # and scan
# ```
def rand(limit)
  r = Random.rand(limit)
  puts "rand #{limit} -> #{r}"
  r
end

# The `sqrt` method returns the square root of a number. Number is made positive, if necessary.
#
# Examples:
#
# ```
# x = x1 - x2 # compute the classical distance formula
# y = y1 - y2 # between two points (x1,y1) (x2,y2)
# distance = sqrt((x*x) - (y*y))
# ```
def sqrt(number)
  r = Math.isqrt(number.abs)
  puts "sqrt #{number} -> #{r}"
  r
end

# These methods provide trigonometric values. `sin`, `cos`, and `tan`, take a degree argument, 0-359, and returns the
# trigonometric value times 100,000. The scaling is necessary since the `crystal-robots` CPU is an integer only machine,
# and trig values are between 0.0 and 1.0. `atan` takes a ratio argument that has been scaled up by 100,000, and returns
# a degree value, between -90 and +90. The resulting calculation should not be scaled to the actual value until the final
# operation, as not to lose accuracy. See programming examples for usage.
#
# TODO: link to programming examples
def sin(degree)
  r = f2i(Math.sin(d2r(degree)))
  puts "sin #{degree} -> #{r}"
  r
end

# See `sin`
def cos(degree)
  r = f2i(Math.cos(d2r(degree)))
  puts "cos #{degree} -> #{r}"
  r
end

# See `sin`
def tan(degree)
  r = f2i(Math.tan(d2r(degree)))
  puts "tan #{degree} -> #{r}"
  r
end

# See `sin`
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
