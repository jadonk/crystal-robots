require "./spec_helper"

alias Interpreter = CrystalRobots::Compiler::Interpreter

describe Interpreter do
  it "runs puts, arithmetic and globals" do
    interpret_puts("global(count, 5)\nputs count + 1\n").should eq [6]
  end

  it "runs while, until, if/elsif/else and break" do
    source = <<-ROBOT
      global(i, 0)
      while i < 5
      i = i + 1
      end
      until i == 0
      i = i - 1
      end
      if i == 0
      puts 1
      elsif i == 1
      puts 2
      else
      puts 3
      end
      j = 0
      while j < 100
      j = j + 1
      break
      end
      puts j
      ROBOT
    interpret_puts(source).should eq [1, 1]
  end

  it "computes && || and ^, evaluating both sides" do
    source = <<-ROBOT
      a = 3 > 2
      b = 2 > 3
      puts a && b
      puts a || b
      puts 5 ^ 3
      ROBOT
    interpret_puts(source).should eq [0, 1, 6]
  end

  it "allows an assignment inside a condition, and a bare builtin call as a call argument" do
    interpret_puts("i = 3\nwhile (n = i) > 0\ni -= 1\nend\nputs n\n").should eq [0]
    interpret_puts("def sum(a, b)\na + b\nend\nputs sum(sqrt 16, sqrt 9)\n").should eq [7]
  end

  it "compound-assigns += -= *= %=" do
    interpret_puts("global(i, 10)\ni += 5\ni -= 2\ni *= 3\ni %= 10\nputs i\n").should eq [((10 + 5 - 2) * 3) % 10]
  end

  it "calls builtins through the host, bare and parenthesized" do
    interpret_puts("puts damage\nputs scan 3, 4\n").should eq [11, 7]
    interpret_puts("puts sqrt(16)\nputs scan(3, 4)\n").should eq [4, 7]
  end

  it "calls user functions, including recursively, with implicit and explicit return" do
    source = <<-ROBOT
      def fact(n)
      if n == 0
      return 1
      end
      n * fact(n - 1)
      end
      puts fact(5)
      ROBOT
    interpret_puts(source).should eq [120]
  end

  it "treats true and false as 1 and 0, and ignores comments" do
    source = <<-ROBOT
      # a leading comment
      puts true # trailing
      puts false
      ROBOT
    interpret_puts(source).should eq [1, 0]
  end

  it "treats a plain top-level assignment as an implicit global, and calls a zero-arg function bare" do
    source = <<-ROBOT
      C1X = 10
      C1Y = 20
      global(count, 0)
      def bump
      count = count + 1
      end
      bump
      bump
      puts C1X + C1Y
      puts count
      ROBOT
    interpret_puts(source).should eq [30, 2]
  end

  it "runs main last" do
    interpret_puts("puts 1\nmain(\"Test\") do\nputs 2\nend\n").should eq [1, 2]
  end
end
