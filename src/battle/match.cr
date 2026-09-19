require "./field"
require "./robot_host"

# Runs several robots' interpreters against one `Field`, interleaved --
# ported in spirit from main.c's own round-robin `cycle()` loop, one
# instruction per robot per round, with `move_robots`/`move_missiles`
# called every `MOTION_CYCLES` rounds -- but built on Crystal's own
# concurrency primitives rather than a port of the C event loop itself.
#
# Each robot's `Interpreter` runs in its own spawned Fiber, synchronized
# with the scheduler through a `Channel` round-trip once per statement
# (`Interpreter#step_channel`/`#done_channel`; see that file's comment
# for why a `Channel`, not bare `Fiber.yield`). The scheduler never polls
# a fiber's own liveness: whether to keep waiting on a robot is decided
# entirely from `Field::Robot#alive?`, state this class already owns and
# updates deterministically, which is what makes ending the match safe --
# a dead robot's fiber is simply never signaled again and sits forever
# suspended, harmless.
module CrystalRobots::Battle
  MOTION_CYCLES = 15

  class Match
    getter field : Field
    getter rounds = 0

    @steps : Array(Channel(Nil))
    @dones : Array(Channel(Nil))
    @hosts : Array(RobotHost)

    # `programs` and `field.robots` must be the same size, in the same
    # order. `cycle_limit` bounds the number of rounds (one instruction
    # per living robot each), so a match always ends even if nobody dies.
    def initialize(@field : Field, programs : Array(Compiler::Program), costs : Compiler::Interpreter::Costs = Compiler::Interpreter::Costs.new, @cycle_limit : Int32 = 500_000)
      @steps = @field.robots.map { Channel(Nil).new }
      @dones = @field.robots.map { Channel(Nil).new }
      @hosts = Array(RobotHost).new(@field.robots.size) { |i| RobotHost.new(@field, i) }
      programs.each_with_index do |program, i|
        step_ch, done_ch, host = @steps[i], @dones[i], @hosts[i]
        spawn(name: @field.robots[i].name) do
          interp = Compiler::Interpreter.new(program, host, costs)
          interp.step_channel = step_ch
          interp.done_channel = done_ch
          begin
            interp.run
          rescue
            # a robot's own runtime error just stops it, not the match
          end
        end
      end
    end

    # Runs to completion: every robot dead but at most one, or the cycle
    # limit reached.
    def run : Nil
      countdown = MOTION_CYCLES
      while @field.robots.count(&.alive?) > 1 && @rounds < @cycle_limit
        @field.robots.each_with_index { |r, i| @dones[i].receive if r.alive? }
        @rounds += 1
        countdown -= 1
        if countdown == 0
          @field.move_robots
          @field.move_missiles
          countdown = MOTION_CYCLES
        end
        @field.robots.each_with_index { |r, i| @steps[i].send(nil) if r.alive? }
      end
    end
  end
end
