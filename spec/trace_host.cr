require "../src/compiler"

# A `Host` that answers sensors from simple formulas and logs every call, so
# the interpreter and the WebAssembly module can be compared step by step.
class TraceHost < CrystalRobots::Compiler::Host
  getter log = [] of String

  def initialize
    @tick = 0
  end

  def scan(degree : Int32, resolution : Int32) : Int32
    @log << "scan #{degree} #{resolution}"
    degree % 90 == 0 ? 100 + degree : 0
  end

  def cannon(degree : Int32, range : Int32) : Int32
    @log << "cannon #{degree} #{range}"
    (@tick += 1) % 2
  end

  def drive(degree : Int32, speed : Int32) : Int32
    @log << "drive #{degree} #{speed}"
    1
  end

  def damage : Int32
    @log << "damage"
    (@tick += 1) * 3 % 100
  end

  def speed : Int32
    @log << "speed"
    (@tick += 1) % 3 == 0 ? 0 : 50
  end

  def loc_x : Int32
    @log << "loc_x"
    (@tick += 1) * 7 % 1000
  end

  def loc_y : Int32
    @log << "loc_y"
    (@tick += 1) * 11 % 1000
  end

  def sleep : Int32
    @log << "sleep"
    0
  end

  def rand(limit : Int32) : Int32
    @log << "rand #{limit}"
    limit <= 0 ? 0 : (@tick += 1) * 13 % limit
  end

  def puts(value : CrystalRobots::Compiler::Value) : Nil
    @log << "puts #{value}"
  end
end
