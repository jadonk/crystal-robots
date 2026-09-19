require "./spec_helper"

# The interpreter and the WASM emitter are two independent readings of
# the same AST. Both bind the builtins to the same stand-in behavior (the
# interpreter's `NullHost`, `run_puts`'s wasmer bindings), so for any
# robot that does not divide, the two engines must print identical
# output -- otherwise one of them has a bug the other does not.
ROBOTS = {
  "arithmetic and comparisons" => <<-ROBOT,
    puts 2 + 3 * 4
    puts (2 + 3) * 4
    puts -5 + 2
    puts 1 < 2
    puts 2 == 3
    ROBOT
  "globals, while, until, if/elsif/else, break" => <<-ROBOT,
    global(count, 0)
    while count < 5
    count = count + 1
    end
    until count == 0
    count = count - 1
    end
    if count == 0
    puts 100
    elsif count == 1
    puts 200
    else
    puts 300
    end
    j = 0
    while j < 100
    j = j + 1
    break
    end
    puts j
    ROBOT
  "functions, recursion, builtins and main" => <<-ROBOT,
    global(shots, 0)
    def fact(n)
    if n == 0
    return 1
    end
    n * fact(n - 1)
    end
    def fire(angle, r)
    shots = shots + 1
    cannon angle, r
    end
    main("Test") do
    puts fact(5)
    puts fire(10, 20)
    puts shots
    puts damage
    puts sqrt 16
    end
    ROBOT
}

describe "the interpreter and the WASM emitter" do
  ROBOTS.each do |name, source|
    wasmer_it "agree on #{name}" do
      interpret_puts(source).should eq run_puts(source)
    end
  end

  ROBOTS.each do |name, source|
    wasmer_it "charge identical cycle totals on #{name}" do
      costs = CrystalRobots::Compiler::Interpreter::Costs.new
      cycles = interpret_cycles(source, costs)
      _puts_out, ticks = run_with_ticks(source, costs)
      ticks.should eq cycles
    end
  end
end
