require "./spec_helper"
require "../src/battle/step_robot"

{% if flag?(:wasmer) %}
  private def install_compiled(field : CrystalRobots::Battle::Field) : Nil
    field.robots.each do |robot|
      program = C::Parser.new(robot.source).program
      emitter = C::WASM_Emitter.new(program, C::Interpreter::Costs.crobots, resumable: true)
      runner = WASMSpec.new(host: CrystalRobots::Battle::RobotHost.new(robot, field))
      instance = runner.load_wasm(emitter.to_wasm)
      step = instance.function("step").not_nil!
      names = program.children(program.root).select { |s| program[s].rule == :def }.map do |s|
        program.lexeme(program.children(program.arg(s, 0))[1])
      end
      robot.external_step = -> : Tuple(Symbol, String?) do
        # Keep the runner (and its wasmer store/imports) alive for the match.
        runner.host
        case step.call.as(Int32)
        when 0 then {:paused, nil}
        when 1 then {:completed, nil}
        else
          code = instance.global("error_code").not_nil!.value.as(Int32)
          name = names[code - 1]? || "unknown"
          {:error, "call depth exceeded #{C::Interpreter::MAX_CALL_DEPTH} in #{name}"}
        end
      end
    end
  end

  private def compiled_battle(entries : Array({String, String}), seed : UInt64, limit : Int64) : CrystalRobots::Battle::Field
    field = CrystalRobots::Battle::Field.new(entries, seed: seed, limit: limit, max_frames: 80)
    install_compiled(field)
    field.run_stepwise
  end

  private def compare_battles(entries : Array({String, String}), seed : UInt64, limit : Int64 = 3000_i64) : Nil
    expected = CrystalRobots::Battle::Field.new(entries, seed: seed, limit: limit, max_frames: 80).run_stepwise
    actual = compiled_battle(entries, seed, limit)
    actual.frames.should eq expected.frames
    actual.cycles.should eq expected.cycles
    actual.robots.map(&.cycles).should eq expected.robots.map(&.cycles)
    actual.robots.map(&.restarts).should eq expected.robots.map(&.restarts)
    actual.robots.map(&.output).should eq expected.robots.map(&.output)
    actual.robots.map(&.error).should eq expected.robots.map(&.error)
    actual.winner.try(&.name).should eq expected.winner.try(&.name)
  end
{% end %}

describe "resumable WASM" do
  wasmer_it "pauses before a builtin and resumes a nested call" do
    source = <<-ROBOT
      def twice(x)
        puts x
        x + x
      end
      main("test") do
        puts twice(7)
      end
      ROBOT
    program = C::Parser.new(source).program
    wasm = C::WASM_Emitter.new(program, C::Interpreter::Costs.crobots, resumable: true).to_wasm
    runner = WASMSpec.new
    instance = runner.load_wasm(wasm)
    instance.memory("memory").should_not be_nil
    instance.global("error_code").should_not be_nil
    step = instance.function("step").not_nil!
    statuses = [] of Int32
    40.times do
      status = step.call.as(Int32)
      statuses << status
      break if status != 0
    end
    statuses.last.should eq 1
    statuses.first.should eq 0
    runner.puts_out.should eq ["7", "14"]
  end

  wasmer_it "matches the interpreter after every charged unit" do
    source = "def inner(x)\n puts x\n x + 1\nend\nmain(\"step\") do\n puts inner(5)\nend\n"
    entries = [{"step", source}]
    native = CrystalRobots::Battle::Field.new(entries, seed: 2_u64)
    compiled = CrystalRobots::Battle::Field.new(entries, seed: 2_u64)
    install_compiled(compiled)
    a = native.robots.first
    b = compiled.robots.first
    a.start_stepwise
    b.start_stepwise
    50.times do
      a.step!
      b.step!
      b.cycles.should eq a.cycles
      b.restarts.should eq a.restarts
      b.output.should eq a.output
      b.error.should eq a.error
    end
  end

  wasmer_it "keeps globals across main restarts" do
    source = "global(n, 0)\nmain(\"counter\") do\n n += 1\n puts n\nend\n"
    compare_battles([{"counter", source}, {"idle", "main(\"idle\") do\n while true\n  sleep\n end\nend\n"}], 1_u64, 90_i64)
  end

  wasmer_it "keeps top level constants while main restarts" do
    source = "BASE = 7\nmain(\"constant\") do\n puts BASE\n BASE += 1\n puts BASE\nend\n"
    compare_battles([{"constant", source}, {"idle", "main(\"idle\") do\n while true\n  sleep\n end\nend\n"}], 1_u64, 180_i64)
  end

  wasmer_it "turns deep recursion into a robot runtime error" do
    source = "def dive\n dive\nend\nmain(\"deep\") do\n dive\nend\n"
    compare_battles([{"deep", source}, {"idle", "main(\"idle\") do\n while true\n  sleep\n end\nend\n"}], 1_u64, 6000_i64)
  end

  wasmer_it "pauses a loop that calls no builtins" do
    source = "main(\"loop\") do\n while true\n  1 + 2\n end\nend\n"
    compare_battles([{"loop", source}, {"idle", "main(\"idle\") do\n while true\n  sleep\n end\nend\n"}], 1_u64, 90_i64)
  end

  wasmer_it "returns zero for division and modulo by zero" do
    source = "main(\"zero\") do\n puts 4 // 0\n puts 4 % 0\n puts (-2147483647 - 1) // -1\n puts (-2147483647 - 1) % -1\nend\n"
    compare_battles([{"zero", source}, {"idle", "main(\"idle\") do\n while true\n  sleep\n end\nend\n"}], 1_u64, 90_i64)
  end

  wasmer_it "matches stepwise battles for every compilable bundled robot" do
    files = Dir.glob("examples/*.cr").sort + Dir.glob("robots/*.md").sort
    sources = files.compact_map do |file|
      text = File.read(file)
      source = file.ends_with?(".md") ? (text.match(/```crystal\n(.*?)```/m).try(&.[1]) || "") : text
      begin
        program = C::Parser.new(source).program
        C::WASM_Emitter.new(program, C::Interpreter::Costs.crobots, resumable: true).to_wasm
        {File.basename(file), source}
      rescue C::WASM_Emitter::Unsupported
        nil
      end
    end
    sources.should_not be_empty
    opponent = sources.find { |name, _| name == "sniper.cr" } || sources.first
    others = sources.reject { |entry| entry == opponent }
    sources.each do |entry|
      (1_u64..3_u64).each do |seed|
        compare_battles([entry, opponent], seed)
        compare_battles([entry, opponent, others[0], others[1]], seed)
      end
    end
  end
end
