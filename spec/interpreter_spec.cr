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

  it "calls builtins through the host" do
    interpret_puts("puts damage\nputs scan 3, 4\n").should eq [11, 7]
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

  it "runs main last" do
    interpret_puts("puts 1\nmain(\"Test\") do\nputs 2\nend\n").should eq [1, 2]
  end
end
