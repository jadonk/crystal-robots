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
    run_puts("puts ((1 + 2) * 3)\n").should eq [9]
  end

  wasmer_it "puts(1) + 2 parses as puts(1 + 2), a known accepted gap (docs/PARSER.md)" do
    run_puts("puts (1) + 2\n").should eq [1]
  end

  wasmer_it "negates a value" do
    run_puts("puts -5 + 2\n").should eq [-3]
  end

  wasmer_it "compound-assigns += -= *= %=" do
    source = <<-ROBOT
      global(i, 10)
      i += 5
      i -= 2
      i *= 3
      i %= 10
      puts i
      ROBOT
    run_puts(source).should eq [((10 + 5 - 2) * 3) % 10]
  end

  wasmer_it "computes / // and %" do
    run_puts("puts 7 / 2\nputs 7 // 2\nputs 7 % 2\n").should eq [3, 3, 1]
  end

  wasmer_it "treats a plain top-level assignment as an implicit global constant" do
    run_puts("C1X = 10\nC1Y = 20\ndef total\nC1X + C1Y\nend\nputs total\n").should eq [30]
  end

  wasmer_it "calls a zero-argument user function without parens" do
    run_puts("global(count, 0)\ndef bump\ncount = count + 1\nend\nbump\nbump\nputs count\n").should eq [2]
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

  wasmer_it "treats true and false as 1 and 0, and ignores comments" do
    run_puts("# a leading comment\nputs true # trailing\nputs false\n").should eq [1, 0]
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

  wasmer_it "calls one- and two-argument builtins with parens the same as bare" do
    run_puts("puts sqrt(16)\n").should eq run_puts("puts sqrt 16\n")
    run_puts("puts scan(3, 4)\n").should eq run_puts("puts scan 3, 4\n")
  end

  it "only imports the builtins the program actually calls" do
    program = CrystalRobots::Compiler::Parser.new("puts damage\n").program
    W.new(program).imports.should eq ["puts", "damage"]
  end

  wasmer_it "calls a user function and uses its implicit last-expression return" do
    source = <<-ROBOT
      def double(n)
      n * 2
      end
      puts double(21)
      ROBOT
    run_puts(source).should eq [42]
  end

  wasmer_it "returns explicitly, short-circuiting the rest of the function" do
    source = <<-ROBOT
      def first_positive(a, b)
      if a > 0
      return a
      end
      b
      end
      puts first_positive(-1, 7)
      puts first_positive(3, 7)
      ROBOT
    run_puts(source).should eq [7, 3]
  end

  wasmer_it "keeps a function's locals separate from a global of the same shape" do
    source = <<-ROBOT
      global(total, 0)
      def add(a, b)
      sum = a + b
      total = total + sum
      sum
      end
      puts add(2, 3)
      puts add(10, 20)
      puts total
      ROBOT
    run_puts(source).should eq [5, 30, 35]
  end

  wasmer_it "recurses" do
    source = <<-ROBOT
      def fact(n)
      if n == 0
      return 1
      end
      n * fact(n - 1)
      end
      puts fact(5)
      ROBOT
    run_puts(source).should eq [120]
  end

  wasmer_it "runs the main block after every other top-level statement" do
    source = <<-ROBOT
      def double(n)
      n * 2
      end
      global(count, 0)
      puts 1
      main("Sniper") do
      puts double(count + 1)
      end
      puts 99
      ROBOT
    run_puts(source).should eq [1, 99, 2]
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
