require "./spec_helper"

describe CrystalRobots do
  it "has a valid version" do
    SemanticVersion.parse(CrystalRobots::VERSION)
  end

  describe "CLI" do
  end

  describe "Robot" do
  end

  describe "Parser" do
    it "can be instantiated" do
      p = CrystalRobots::Compiler::Parser.new("")
      p.should_not eq nil
    end

    it "tokenizes single keyword" do
      t = CrystalRobots::Compiler::Parser.tokenize(0, " def")
      t.size.should eq 1
      t[0].type.should eq CrystalRobots::Compiler::Type::DefKeyword
      t[0].index.should eq [1]
    end

    it "tokenizes single builtin" do
      t = CrystalRobots::Compiler::Parser.tokenize(0, " puts")
      t.size.should eq 1
      t[0].type.should eq CrystalRobots::Compiler::Type::OneArgBuiltin
      t[0].index.should eq [1]
    end

    it "tokenizes single string" do
      t = CrystalRobots::Compiler::Parser.tokenize(0, "  \"string\" ")
      t.size.should eq 1
      t[0].type.should eq CrystalRobots::Compiler::Type::String
      t[0].index.should eq [2]
    end

    it "tokenizes builtin followed by string" do
      p = CrystalRobots::Compiler::Parser.new(" puts \"string\"")
      p.program[0].size.should eq 2
      p.program[0][0].type.should eq CrystalRobots::Compiler::Type::OneArgBuiltin
      p.program[0][0].index.should eq [1]
      p.program[0][0].value.should eq "puts"
      p.program[0][1].type.should eq CrystalRobots::Compiler::Type::String
      p.program[0][1].index.should eq [6]
      p.program[0][1].value.should eq "\"string\""
    end

    it "tokenizes numbers" do
      t = CrystalRobots::Compiler::Parser.tokenize(0, " 32 \n  -11 39.5")
      t.size.should eq 3
      t[0].type.should eq CrystalRobots::Compiler::Type::Number
      t[0].index.should eq [1]
      t[0].value.should eq "32"
      t[1].type.should eq CrystalRobots::Compiler::Type::Number
      t[1].index.should eq [7]
      t[1].value.should eq "-11"
      t[2].type.should eq CrystalRobots::Compiler::Type::Number
      t[2].index.should eq [11]
      t[2].value.should eq "39.5"
    end

    it "throws exception with bad keyword" do
      expect_raises(CrystalRobots::Compiler::Parser::Error, "Unexpected token f") do
        p = CrystalRobots::Compiler::Parser.new(" def foo")
      end
    end

    it "can produce token strings" do
      p = CrystalRobots::Compiler::Parser.new(" puts \"string\"")
      p.to_s.should eq "∊🐍\n" + "❤\n" + "⏹"
    end

    it "can recursively tokenize/parse" do
      p = CrystalRobots::Compiler::Parser.new(" puts \"string\"")
      ast = p.program
      s = p.to_s
      s.should eq "∊🐍\n❤\n⏹"
      "#{ast}".should eq "CrystalRobots::Compiler::Program(@ast=[[CrystalRobots::Compiler::Node(@type=CrystalRobots::Compiler::Type::OneArgBuiltin, @value=\"puts\", @index=[1]), CrystalRobots::Compiler::Node(@type=CrystalRobots::Compiler::Type::String, @value=\"\\\"string\\\"\", @index=[6])], [CrystalRobots::Compiler::Node(@type=CrystalRobots::Compiler::Type::OneArgStatement, @value=\"∊🐍\", @index=[0, 1])], [CrystalRobots::Compiler::Node(@type=CrystalRobots::Compiler::Type::Program, @value=\"❤\", @index=[0])]])"
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
  end
end
