require "./spec_helper"

describe CrystalRobots do
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

  describe "Compiler::WASM_Emitter" do
    it "has an emitter" do
      f = CrystalRobots::Compiler.compile_to_wasm(" puts 42")
      # https://webassembly.github.io/wabt/demo/wat2wasm/
      f.should eq Bytes[
        0, 0x61, 0x73, 0x6d,                                     # WASM_BINARY_MAGIC
        1, 0, 0, 0,                                              # WASM_BINARY_VERSION
        0x01,                                                    # section "Type" - section code
        19,                                                      # section size
        0x04,                                                    # num types
        0x60,                                                    # func type 0 - func
        0,                                                       # num params
        0,                                                       # num results
        0x60,                                                    # func type 1 - func
        0,                                                       # num params
        1,                                                       # num results
        0x7f,                                                    # i32
        0x60,                                                    # func type 2 - func
        1,                                                       # num params
        0x7f,                                                    # i32
        1,                                                       # num results
        0x7f,                                                    # i32
        0x60,                                                    # func type 3 - func
        2,                                                       # num params
        0x7f,                                                    # i32
        0x7f,                                                    # i32
        1,                                                       # num results
        0x7f,                                                    # i32
        2, 12, 1, 3, 101, 110, 118, 4, 112, 117, 116, 115, 0, 2, # Section "Import"
        3, 2, 1, 1,                                              # Section "Function"
        7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 1,                      # Section "Export"
        10, 8, 1, 6, 0, 65, 42, 16, 0, 0xb                       # Section "Code"
      ]
      # ; section "Import" (2)
      # 000001d: 02                                        ; section code
      # 000001e: 00                                        ; section size (guess)
      # 000001f: 01                                        ; num imports
      # ; import header 0
      # 0000020: 03                                        ; string length
      # 0000021: 656e 76                                    ; import module name - "env"
      # 0000024: 04                                        ; string length
      # 0000025: 7075 7473                                  ; import field name - "puts"
      # 0000029: 00                                        ; import kind
      # 000002a: 02                                        ; import signature index
      # 000001e: 0c                                        ; FIXUP section size
      # ; section "Function" (3)
      # 000002b: 03                                        ; section code
      # 000002c: 02                                        ; section size
      # 000002d: 01                                        ; num functions
      # 000002e: 01                                        ; function 0 signature index
      # ; section "Export" (7)
      # 000002f: 07                                        ; section code
      # 0000030: 07                                        ; section size
      # 0000031: 01                                        ; num exports
      # 0000032: 03                                        ; string length
      # 0000033: 7275 6e                                   ; export name - "run"
      # 0000036: 00                                        ; export kind
      # 0000037: 01                                        ; export func index
      # ; section "Code" (10)
      # 0000038: 0a                                        ; section code
      # 0000039: 08                                        ; section size
      # 000003a: 01                                        ; num functions
      # ; function body 0
      # 000003b: 06                                        ; FIXUP func body size
      # 000003c: 00                                        ; local decl count
      # 000003d: 41                                        ; i32.const
      # 000003e: 2a                                        ; i32 literal
      # 000003f: 10                                        ; call
      # 0000040: 00                                        ; function index
      # 0000041: 0b                                        ; end
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
      run.call().should eq 0
      w.last_puts.should eq "42"
    end
  end
end
