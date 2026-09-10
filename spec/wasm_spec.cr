require "./spec_helper"
require "./trace_host"

alias W = CrystalRobots::Compiler::WASM_Emitter

# Robots that terminate, exercising every construct the emitter supports.
DIFFERENTIAL = {
  "arithmetic" => <<-ROBOT,
    puts 7 // 2
    puts -7 // 2
    puts 7 % 3
    puts -7 % 3
    puts 7 % -3
    puts 5 // 0
    puts 5 % 0
    puts (3 > 2) && (2 > 3)
    puts (3 > 2) || (2 > 3)
    puts 1 - 2 - 3 * 4 < 5
    ROBOT
  "variables and blocks" => <<-ROBOT,
    C = 10
    global(count, 2)
    i = 0
    while i < 5
      i += 1
      if i == 2
        puts 20
      elsif i % 2 == 1
        puts i
      else
        count += i
      end
    end
    until count > 20
      count *= 2
    end
    puts count
    case count % 3
    when 0
      puts 300
    when 1
      puts 301
    else
      puts 302
    end
    j = 0
    while true
      j += 1
      break
    end
    puts j + C
    ROBOT
  "functions and builtins" => <<-ROBOT,
    SCALE = 100000
    global(d, 0)
    def dist(x1, y1, x2, y2)
      x = x1 - x2
      y = y1 - y2
      sqrt(x * x + y * y)
    end
    def bump(n)
      d += n
      return d * 2
      puts 999
    end
    def loud
      puts sin(30) + cos(60)
    end
    main("Test") do
      angle = rand(360)
      range = scan(angle, 5)
      if range > 0
        cannon(angle, range)
      end
      drive(90, 40)
      while speed > 0
        loud
      end
      puts dist(loc_x, loc_y, 0, 0)
      puts bump(3)
      puts bump(4)
      puts atan(SCALE) + damage
      sleep
    end
    ROBOT
}

describe "WASM back end" do
  it "compiles every example robot" do
    Dir.glob("examples/*.cr").sort.each do |file|
      bytes = CrystalRobots::Compiler.compile_to_wasm(File.read(file))
      bytes[0, 4].should eq Bytes[0, 0x61, 0x73, 0x6d]
    end
  end

  it "imports only the builtins a program uses, in a fixed order" do
    e = W.new(CrystalRobots::Compiler::Parser.new("drive(0, 1)\nputs loc_x").program)
    e.importSection.should eq(
      Bytes[2, 36, 3] +
      Bytes[3] + "env".to_slice + Bytes[4] + "puts".to_slice + Bytes[0, 2] +
      Bytes[3] + "env".to_slice + Bytes[5] + "drive".to_slice + Bytes[0, 3] +
      Bytes[3] + "env".to_slice + Bytes[5] + "loc_x".to_slice + Bytes[0, 1])
  end

  it "rejects strings" do
    expect_raises(W::Unsupported, /strings/) do
      CrystalRobots::Compiler.compile_to_wasm("puts \"hi\"")
    end
  end

  DIFFERENTIAL.each do |name, source|
    wasmer_it "matches the interpreter on #{name}" do
      program = CrystalRobots::Compiler::Parser.new(source).program
      CrystalRobots::Compiler::Checker.check(program).should be_empty
      expected_host = TraceHost.new
      CrystalRobots::Compiler::Interpreter.puts_clear
      CrystalRobots::Compiler::Interpreter.new(program, expected_host, 100_000).run
      expected = CrystalRobots::Compiler::Interpreter.puts_out.lines
      actual_host = TraceHost.new
      w = WASMSpec.new(host: actual_host)
      w.run(source).should eq expected
      actual_host.log.should eq expected_host.log
      expected.should_not be_empty
    end
  end
end
