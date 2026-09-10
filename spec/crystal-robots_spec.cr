require "./spec_helper"

alias C = CrystalRobots::Compiler

describe CrystalRobots do
  it "has a valid version" do
    SemanticVersion.parse(CrystalRobots::VERSION)
  end

  describe "CLI" do
    it "can be called without the command-line option parser" do
      c = CrystalRobots::CLI.new(run_parser: false)
      c.run.should eq 1
    end

    it "can be asked to compile a robot and output WebAssembly" do
      c = CrystalRobots::CLI.new(run_parser: false, robot_to_compile: "examples/test.cr", outfile: "examples/test.wasm")
      c.run.should eq 0
      File.size("examples/test.wasm").should be > 8
    end
  end

  describe "Compiler" do
    describe "Program" do
      it "can be instantiated" do
        p = C::Program.new("")
        p.text.should eq ""
        p.parsed?.should be_false
      end

      it "appends each pass to the source behind a pass token" do
        p = C::Program.new("source")
        p.source.should eq "source"
        p.add_pass([] of Int32, :lex)
        p.source.should eq "sourceŖ"
        p.pass.should eq [7]
        p.passes.should eq 1
      end

      it "can hold tokens" do
        p = C::Program.new("")
        p.push(C::Type::Number, 1, 2)
        "#{p.node(0)}".should eq "'№' from 1 length 2 level 0 rule lex"
        p.size.should eq 1
      end
    end

    describe "Parser" do
      it "can be instantiated with an empty program" do
        p = C::Parser.new
        p.program.parsed?.should be_true
        p.program.to_s.should eq "⏹"
      end

      it "lexes a keyword" do
        p = C::Program.new(" def")
        C::Parser.lex(p).should eq "🔕⏎"
        p.type(0).should eq C::Type::DefKeyword
        p.start(0).should eq 1
        p.count(0).should eq 3
        p.value(0).should eq "def"
      end

      it "lexes a builtin" do
        p = C::Program.new(" puts")
        C::Parser.lex(p).should eq "∊⏎"
        p.type(0).should eq C::Type::OneArgMethod
        p.start(0).should eq 1
        p.count(0).should eq 4
      end

      it "lexes a string" do
        p = C::Program.new("  \"string\" ")
        C::Parser.lex(p).should eq "🐍⏎"
        p.type(0).should eq C::Type::String
        p.start(0).should eq 2
        p.value(0).should eq "\"string\""
      end

      it "lexes a builtin followed by a string" do
        p = C::Program.new(" puts \"string\"")
        C::Parser.lex(p).should eq "∊🐍⏎"
        p.value(0).should eq "puts"
        p.type(1).should eq C::Type::String
        p.start(1).should eq 6
        p.value(1).should eq "\"string\""
      end

      it "lexes numbers, operators and newlines" do
        p = C::Program.new(" 32 \n  11 + 39")
        C::Parser.lex(p).should eq "№⏎№⊕№⏎"
        p.value(0).should eq "32"
        p.type(1).should eq C::Type::Newline
        p.value(2).should eq "11"
        p.type(3).should eq C::Type::AddOperator
        p.value(4).should eq "39"
      end

      it "lexes identifiers and two-character operators" do
        p = C::Program.new("foo += bar_2 && x <= 3")
        C::Parser.lex(p).should eq "𝑥➕𝑥∧𝑥≼№⏎"
        p.value(0).should eq "foo"
        p.value(2).should eq "bar_2"
      end

      it "collapses runs of newlines and semicolons and drops comments" do
        p = C::Program.new("\n\na = 1;;\n# note\n\n b = 2\n")
        C::Parser.lex(p).should eq "𝑥＝№⏎𝑥＝№⏎"
      end

      it "raises on an unexpected character" do
        expect_raises(C::Parser::Error, "Unexpected character '@' at 1:8") do
          C::Parser.new("puts 1 @ 2")
        end
      end

      it "reduces a puts statement to a program" do
        p = C::Parser.new(" puts \"string\"").program
        p.to_s.should eq "⏹"
        p.rules.should eq [:lex, :command1, :exprstmt, :program]
        p.derivation.lines[0].should eq "  0 lex         ∊🐍⏎"
      end

      it "reduces tighter operators first" do
        p = C::Parser.new("puts 2+(1+2)//2*4").program
        p.rules.should eq [:lex, :add, :paren, :mul, :mul, :add, :command1, :exprstmt, :program]
      end

      it "is left associative" do
        p = C::Parser.new("x = 1 - 2 - 3").program
        p.rules.should eq [:lex, :add, :add, :assign, :exprstmt, :program]
        # the first reduction covers "1 - 2", the glyphs at positions 2..4
        first = p.ast.find! { |n| n.rule == :add }
        p.value(first).should eq "№⊖№"
        p.source[first.start - 2, 2].should eq "𝑥＝"
      end

      it "is right associative for assignment" do
        p = C::Parser.new("x = y = 1").program
        p.rules.should eq [:lex, :assign, :assign, :exprstmt, :program]
      end

      it "parses assignment inside a condition and nested blocks" do
        src = <<-ROBOT
          while (range = scan(angle, res)) > 0
            if (range > 700)
              drive(angle, 50)
            else
              cannon(angle, range)
            end
          end
          ROBOT
        p = C::Parser.new(src).program
        p.parsed?.should be_true
        p.rules.last(3).should eq [:if, :while, :program]
      end

      it "exposes the children of every reduction" do
        p = C::Parser.new("puts 1+2").program
        stmts = p.children(p.root)
        stmts.size.should eq 1
        expr = p.arg(stmts[0], 0)
        p[expr].rule.should eq :command1
        sum = p.arg(expr, 1)
        p[sum].rule.should eq :add
        p.children(sum).map { |i| p.value(i) }.should eq ["1", "+", "2"]
        p.location(sum).should eq({1, 6})
      end

      it "reports the location of a token it cannot reduce" do
        expect_raises(C::Parser::Error, /Cannot reduce 🅸 \(IfHead\) .* at 1:1/) do
          C::Parser.new("if x\n  puts 1\n")
        end
      end

      it "gives up after the pass budget" do
        # every `1+` costs a pass; the budget stops runaway inputs
        C::Parser.max_passes = 50
        begin
          expect_raises(C::Parser::Error, /more than 50 passes/) do
            C::Parser.new("puts " + "1+" * 100 + "1")
          end
        ensure
          C::Parser.max_passes = 20_000
        end
      end

      it "parses every example robot" do
        Dir.glob("examples/*.cr").sort.each do |file|
          p = C::Parser.new(File.read(file)).program
          p.parsed?.should be_true
        end
      end

      it "uses only glyphs that name a Type in its grammar" do
        C::Parser::GRAMMAR.each do |rule|
          rule.regex.source.each_char do |ch|
            next if ch.ord < 128
            C::Type.from_value?(ch.ord).should_not be_nil
          end
        end
      end
    end

    describe "WASM_Emitter" do
      it "has an emitter" do
        f = C.compile_to_wasm(" puts 42")
        # https://webassembly.github.io/wabt/demo/wat2wasm/
        f.should eq Bytes[
          0, 0x61, 0x73, 0x6d,    # WASM_BINARY_MAGIC
          1, 0, 0, 0,             # WASM_BINARY_VERSION
          0x01,                   # section "Type" - section code
          19,                     # section size
          0x04,                   # num types
          0x60,                   # func type 0 - func
          0,                      # num params
          0,                      # num results
          0x60,                   # func type 1 - func
          0,                      # num params
          1,                      # num results
          0x7f,                   # i32
          0x60,                   # func type 2 - func
          1,                      # num params
          0x7f,                   # i32
          1,                      # num results
          0x7f,                   # i32
          0x60,                   # func type 3 - func
          2,                      # num params
          0x7f,                   # i32
          0x7f,                   # i32
          1,                      # num results
          0x7f,                   # i32
          2,                      # section "Import" - section code
          12,                     # section size
          1,                      # num imports
          3,                      # import header 0 - string length
          0x65, 0x6e, 0x76,       # import module name - "env"
          4,                      # string length
          0x70, 0x75, 0x74, 0x73, # import field name - "puts"
          0,                      # import kind
          2,                      # import signature index
          3,                      # section "Function" - section code
          2,                      # section size
          1,                      # num functions
          1,                      # function 0 signature index
          7,                      # section "Export" - section code
          7,                      # section size
          1,                      # num exports
          3,                      # string length
          0x72, 0x75, 0x6e,       # export name - "run"
          0,                      # export kind
          1,                      # export func index
          10,                     # section "Code" - section code
          11,                     # section size
          1,                      # num functions
          9,                      # function body 0 - func body size
          0,                      # local decl count
          0x41,                   # i32.const
          42,                     # i32 literal
          0x10,                   # call
          0,                      # function index (env.puts)
          0x1a,                   # drop the value puts returned
          0x41,                   # i32.const
          0,                      # run returns 0
          0x0b,                   # end
        ]
      end

      it "emits integer expressions" do
        f = C.compile_to_wasm("puts 1+2")
        f[-11..].should eq Bytes[0x41, 1, 0x41, 2, 0x6a, 0x10, 0, 0x1a, 0x41, 0, 0x0b]
      end

      it "encodes negative constants" do
        f = C.compile_to_wasm("puts -1")
        f[-11..].should eq Bytes[0x41, 0, 0x41, 1, 0x6b, 0x10, 0, 0x1a, 0x41, 0, 0x0b]
      end

      it "rejects what it cannot emit yet" do
        expect_raises(C::WASM_Emitter::Unsupported, /strings/) do
          C.compile_to_wasm("puts \"text\"")
        end
      end

      it "gives functions with many parameters their own type" do
        f = C.compile_to_wasm("def f(a, b, c)\n  a + b + c\nend\nputs f(1, 2, 3)")
        f[8, 4].should eq Bytes[1, 26, 5, 0x60] # type section with a fifth entry
      end

      wasmer_it "test function should load the emitted WASM" do
        file = C.compile_to_wasm(" puts 42")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        i.should_not be_nil
      end

      wasmer_it "test function should find exported function" do
        file = C.compile_to_wasm(" puts 128 ")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        run = i.function("run")
        run.should_not be_nil
      end

      wasmer_it "emitted function should run" do
        file = C.compile_to_wasm("puts 42")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        run = i.function("run").not_nil!
        run.call.should eq 0
        w.last_puts.should eq "42"
      end

      wasmer_it "evaluates expressions like the interpreter" do
        file = C.compile_to_wasm("puts 2+(1+2)//2*4")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        i.function("run").not_nil!.call
        w.last_puts.should eq "6"
      end
    end

    describe "Interpreter" do
      it "returns success" do
        C.interpret("puts 42").should eq 0
      end

      it "performs multiple statements" do
        C.interpret("puts 42 \n puts 11; puts 19").should eq 0
      end

      it "captures output from puts" do
        C::Interpreter.puts_clear
        C.interpret("puts 1\nputs 2\nputs 3")
        C::Interpreter.puts_out.should eq "1\n2\n3"
      end

      it "evaluates simple expressions without parentheses" do
        C::Interpreter.puts_clear
        C.interpret("puts 1+2")
        C::Interpreter.puts_out.should eq "3"
      end

      it "evaluates simple expressions with parentheses" do
        C::Interpreter.puts_clear
        C.interpret("puts 2*(1+2)")
        C::Interpreter.puts_out.should eq "6"
      end

      it "evaluates expressions with precedence and associativity" do
        C::Interpreter.puts_clear
        C.interpret("puts 2+(1+2)//2*4\nputs 1 - 2 - 3\nputs -2 * 3\nputs 7 % 4 == 3 && 1 < 2")
        C::Interpreter.puts_out.should eq "6\n-4\n-6\n1"
      end

      it "assigns variables and compound assignments" do
        C::Interpreter.puts_clear
        C.interpret("x = 1\ny = x = x + 1\nx += 3\ny *= 4\nputs x\nputs y")
        C::Interpreter.puts_out.should eq "5\n8"
      end

      it "runs if, elsif, else, while, until and break" do
        C::Interpreter.puts_clear
        src = <<-ROBOT
          i = 0
          while true
            i += 1
            if i == 1
              puts 10
            elsif i == 2
              puts 20
            else
              break
            end
          end
          until i >= 5
            i += 1
          end
          puts i
          ROBOT
        C.interpret(src)
        C::Interpreter.puts_out.should eq "10\n20\n5"
      end

      it "selects with case and when" do
        C::Interpreter.puts_clear
        C.interpret("c = 2\ncase c\nwhen 1\n puts 100\nwhen 2\n puts 200\nelse\n puts 300\nend")
        C::Interpreter.puts_out.should eq "200"
      end

      it "calls user functions with explicit and implicit returns, globals and constants" do
        C::Interpreter.puts_clear
        src = <<-ROBOT
          SCALE = 10
          global(count, 0)
          def bump(n)
            count += n
            return count * SCALE
          end
          def twice(a, b)
            (a + b) * 2
          end
          def tick
            count += 1
          end
          main("Test") do
            puts bump(2)
            tick
            puts twice(count, 1)
            puts count
          end
          ROBOT
        C.interpret(src)
        C::Interpreter.puts_out.should eq "20\n8\n3"
      end

      it "reports a step limit instead of looping forever" do
        p = C::Parser.new("while true\nend").program
        expect_raises(C::Interpreter::StepLimit) do
          C::Interpreter.new(p, C::NullHost.new, 100).run
        end
      end

      it "runs every example robot against the null host until the step limit" do
        Dir.glob("examples/*.cr").sort.each do |file|
          p = C::Parser.new(File.read(file)).program
          interpreter = C::Interpreter.new(p, C::NullHost.new, 20_000)
          begin
            interpreter.run.should eq 0
          rescue C::Interpreter::StepLimit
            interpreter.steps.should be > 20_000
          end
        end
      end
    end
  end
end

describe CrystalRobots::Compiler::Checker do
  it "accepts every example robot" do
    Dir.glob("examples/*.cr").sort.each do |file|
      p = C::Parser.new(File.read(file)).program
      C::Checker.check(p).should eq([] of C::Checker::Problem)
    end
  end

  it "reports undefined names, arity, return and break misuse with locations" do
    src = <<-ROBOT
      global(g, 0)
      def two(a, b)
        a + b + c
      end
      def two(x)
        x
      end
      main("T") do
        y = two(1)
        z += 1
        puts nope
        return 1
        while true
          break
        end
        break
        g = y
        puts two(1, 2)
      end
      ROBOT
    problems = C::Checker.check(C::Parser.new(src).program).map(&.to_s)
    problems.should eq [
      "function two is defined twice at 5:5",
      "undefined variable or function c at 3:11",
      "undefined variable z at 10:3",
      "undefined variable or function nope at 11:8",
      "return outside of a def at 12:3",
      "break outside of a loop at 16:3",
      "two takes 1 arguments but is called with 2 at 18:8",
    ]
  end
end
