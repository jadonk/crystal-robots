require "./spec_helper"

alias W = CrystalRobots::Compiler::WASM_Emitter

describe W do
  it "is the 8-byte magic header and version at the start of every module" do
    W.minimal_module.should eq Bytes[0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]
  end

  wasmer_it "compiles and runs one puts statement" do
    run_puts("puts 42\n").should eq [42]
  end

  wasmer_it "compiles and runs several puts statements in order" do
    run_puts("puts 1\nputs 2\nputs 3\n").should eq [1, 2, 3]
  end

  wasmer_it "gives * higher precedence than +" do
    run_puts("puts 1 + 2 * 3\n").should eq [7]
  end

  wasmer_it "is left associative within a precedence level" do
    run_puts("puts 10 - 2 - 3\n").should eq [5]
  end

  wasmer_it "lets parentheses override precedence" do
    run_puts("puts (1 + 2) * 3\n").should eq [9]
  end

  wasmer_it "negates a value" do
    run_puts("puts -5 + 2\n").should eq [-3]
  end

  wasmer_it "computes / // and %" do
    run_puts("puts 7 / 2\nputs 7 // 2\nputs 7 % 2\n").should eq [3, 3, 1]
  end

  wasmer_it "declares a global and reads it back" do
    run_puts("global(count, 5)\nputs count\n").should eq [5]
  end

  wasmer_it "assigns to a global and keeps mutating it" do
    run_puts("global(count, 0)\ncount = count + 1\ncount = count + 1\nputs count\n").should eq [2]
  end

  wasmer_it "computes comparisons" do
    run_puts("puts 1 < 2\nputs 2 < 1\nputs 3 == 3\nputs 3 != 3\nputs 5 >= 5\n").should eq [1, 0, 1, 0, 1]
  end

  wasmer_it "counts up in a while loop" do
    run_puts("global(i, 0)\nwhile i < 5\ni = i + 1\nend\nputs i\n").should eq [5]
  end

  wasmer_it "counts down in an until loop" do
    run_puts("global(i, 5)\nuntil i == 0\ni = i - 1\nend\nputs i\n").should eq [0]
  end

  wasmer_it "break stops a while loop before its condition would" do
    run_puts("global(i, 0)\nwhile i < 100\ni = i + 1\nbreak\nend\nputs i\n").should eq [1]
  end

  wasmer_it "takes the if branch" do
    run_puts("if 1 == 1\nputs 10\nend\n").should eq [10]
  end

  wasmer_it "takes the else branch" do
    run_puts("if 1 == 2\nputs 10\nelse\nputs 20\nend\n").should eq [20]
  end

  wasmer_it "takes the matching elsif branch" do
    run_puts("global(n, 2)\nif n == 1\nputs 1\nelsif n == 2\nputs 2\nelse\nputs 3\nend\n").should eq [2]
  end

  wasmer_it "calls a zero-argument builtin" do
    run_puts("puts damage\nputs speed\n").should eq [11, 22]
  end

  wasmer_it "calls a two-argument builtin with both arguments in order" do
    run_puts("puts scan 3, 4\n").should eq [7]
  end

  wasmer_it "calls the math one-argument builtins" do
    run_puts("puts sqrt(16)\nputs sin(90)\nputs cos(0)\n").should eq [4, 1, 1]
  end

  it "only imports the builtins the program actually calls" do
    program = CrystalRobots::Compiler::Parser.new("puts damage\n").program
    W.new(program).imports.should eq ["puts", "damage"]
  end

  wasmer_it "counts fizzbuzz-style with if/elsif/else inside a while loop" do
    source = <<-ROBOT
      global(i, 1)
      while i < 4
      if i == 1
      puts 100
      elsif i == 2
      puts 200
      else
      puts 300
      end
      i = i + 1
      end
      ROBOT
    run_puts(source).should eq [100, 200, 300]
  end
end
