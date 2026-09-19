require "./field"
require "../compiler/interpreter"

# One robot's view of a `Field`, implementing `Compiler::Host` -- the
# seam every earlier commit's `NullHost` stood in for. Ported from
# intrins.c: `sin`/`cos`/`tan` are scaled by 100000, the way CROBOTS's
# own fixed-point trig is, and `atan` takes a ratio scaled the same way
# and returns a plain degree -- rabbit.cr and sniper.cr's own
# `atan((scale * y) / x)` assumes exactly this, `scale` being 100000 in
# both. `NullHost`'s versions of these were arbitrary stand-in values for
# testing without a battlefield; these are the real thing.
module CrystalRobots::Battle
  SCALE_F = 100_000.0

  class RobotHost < Compiler::Host
    def initialize(@field : Field, @robot_index : Int32)
    end

    def puts(n : Int32) : Int32
      n
    end

    def scan(angle : Int32, resolution : Int32) : Int32
      @field.scan(@robot_index, angle, resolution)
    end

    def cannon(angle : Int32, range : Int32) : Int32
      @field.fire_missile(@robot_index, angle, range) ? 1 : 0
    end

    def drive(heading : Int32, speed : Int32) : Int32
      @field.drive(@robot_index, heading, speed)
      1
    end

    def damage : Int32
      @field.robots[@robot_index].damage
    end

    def speed : Int32
      @field.robots[@robot_index].speed
    end

    def loc_x : Int32
      @field.robots[@robot_index].x // CLICK
    end

    def loc_y : Int32
      @field.robots[@robot_index].y // CLICK
    end

    # Not part of the CROBOTS this was ported from -- crystal-robots's
    # own addition, for a robot that has nothing to do this cycle
    # (target.cr's whole body). No battlefield effect of its own.
    def sleep : Int32
      0
    end

    def rand(n : Int32) : Int32
      @field.rand(n)
    end

    def sqrt(n : Int32) : Int32
      Math.sqrt(n.abs.to_f64).to_i32
    end

    def sin(n : Int32) : Int32
      Battle.lsin(n.remainder(360).to_i32).to_i32
    end

    def cos(n : Int32) : Int32
      Battle.lcos(n.remainder(360).to_i32).to_i32
    end

    def tan(n : Int32) : Int32
      deg = n.remainder(360)
      (Math.tan(deg.to_f * Math::PI / 180) * SCALE_F).to_i32
    end

    def atan(n : Int32) : Int32
      (Math.atan(n.to_f / SCALE_F) * 180.0 / Math::PI).to_i32
    end
  end
end
