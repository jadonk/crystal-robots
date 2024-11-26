require "./spec_helper"

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
    end
  end

  describe "Robot" do
  end

  describe "Compiler" do
    describe "Parser" do
      it "can be instantiated" do
        p = CrystalRobots::Compiler::Parser.new("")
        p.should_not eq nil
      end

      it "tokenizes single keyword" do
        p = CrystalRobots::Compiler::Program.new
        t = CrystalRobots::Compiler::Parser.tokenize(p, " def")
        t.size.should eq 1
        t[0].type.should eq CrystalRobots::Compiler::Type::DefKeyword
        t[0].index.should eq 1
      end

      it "tokenizes single builtin" do
        p = CrystalRobots::Compiler::Program.new
        t = CrystalRobots::Compiler::Parser.tokenize(p, " puts")
        t.size.should eq 1
        t[0].type.should eq CrystalRobots::Compiler::Type::OneArgMethod
        t[0].index.should eq 1
      end

      it "tokenizes single string" do
        p = CrystalRobots::Compiler::Program.new
        t = CrystalRobots::Compiler::Parser.tokenize(p, "  \"string\" ")
        t.size.should eq 1
        t[0].type.should eq CrystalRobots::Compiler::Type::String
        t[0].index.should eq 2
      end

      it "tokenizes builtin followed by string" do
        p = CrystalRobots::Compiler::Parser.new(" puts \"string\"")
        p.program[0].size.should eq 2
        p.program[0][0].type.should eq CrystalRobots::Compiler::Type::OneArgMethod
        p.program[0][0].index.should eq 1
        p.program[0][0].value.should eq "puts"
        p.program[0][1].type.should eq CrystalRobots::Compiler::Type::String
        p.program[0][1].index.should eq 6
        p.program[0][1].value.should eq "\"string\""
      end

      it "tokenizes numbers" do
        p = CrystalRobots::Compiler::Program.new
        t = CrystalRobots::Compiler::Parser.tokenize(p, " 32 \n  -11 39.5")
        t.size.should eq 3
        t[0].type.should eq CrystalRobots::Compiler::Type::Number
        t[0].index.should eq 1
        t[0].value.should eq "32"
        t[1].type.should eq CrystalRobots::Compiler::Type::Number
        t[1].index.should eq 7
        t[1].value.should eq "-11"
        t[2].type.should eq CrystalRobots::Compiler::Type::Number
        t[2].index.should eq 11
        t[2].value.should eq "39.5"
      end

      it "throws exception with bad keyword" do
        expect_raises(CrystalRobots::Compiler::Parser::Error, "Unexpected token f") do
          p = CrystalRobots::Compiler::Parser.new(" def foo")
        end
      end

      it "can produce token strings" do
        p = CrystalRobots::Compiler::Parser.new(" puts \"string\"")
        s = p.program.to_s
        s.should eq "∊🐍\n❤\n⏹\n@(3,0)"
      end
    end

    describe "WASM_Emitter" do
      it "has an emitter" do
        f = CrystalRobots::Compiler.compile_to_wasm(" puts 42")
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
          8,                      # section size
          1,                      # num functions
          6,                      # function body 0 - func body size
          0,                      # local decl count
          0x41,                   # i32.const
          42,                     # i32 literal
          0x10,                   # call
          0,                      # function index
          0x0b,                   # end
        ]
      end

      it "test function should load the emited WASM" do
        file = CrystalRobots::Compiler.compile_to_wasm(" puts 42")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        i.should_not be_nil
      end

      it "test function should find exported function" do
        file = CrystalRobots::Compiler.compile_to_wasm(" puts 128 ")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        run = i.function("run")
        run.should_not be_nil
      end

      it "emitted function should run" do
        file = CrystalRobots::Compiler.compile_to_wasm("puts 42")
        w = WASMSpec.new("")
        i = w.load_wasm(file)
        run = i.function("run").not_nil!
        run.call.should eq 0
        w.last_puts.should eq "42"
      end
    end

    describe "Interpreter" do
      it "returns success" do
        CrystalRobots::Compiler.interpret("puts 42").should eq 0
      end

      it "performs multiple statments" do
        CrystalRobots::Compiler.interpret("puts 42 puts 11 puts 19").should eq 0
      end

      it "captures output from puts" do
        CrystalRobots::Compiler::Interpreter.puts_clear
        CrystalRobots::Compiler.interpret("puts 1 puts 2 puts 3")
        CrystalRobots::Compiler::Interpreter.puts_out.should eq "1\n" + "2\n" + "3"
      end

      it "evaluates simple expressions without parentheses" do
        CrystalRobots::Compiler::Interpreter.puts_clear
        CrystalRobots::Compiler.interpret("puts 1+2")
        CrystalRobots::Compiler::Interpreter.puts_out.should eq "3"
      end
    end
  end
end
