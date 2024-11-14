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
        0, 0x61, 0x73, 0x6d,                                                            # WASM_BINARY_MAGIC
        1, 0, 0, 0,                                                                     # WASM_BINARY_VERSION
        1, 19, 4, 96, 0, 0, 96, 0, 1, 127, 96, 1, 127, 1, 127, 96, 2, 127, 127, 1, 127, # Section "Type"
        2, 12, 1, 3, 101, 110, 118, 4, 112, 117, 116, 115, 0, 1,                        # Section "Import"
        3, 2, 1, 0,                                                                     # Section "Function"
        7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 1,                                             # Section "Export"
        10, 8, 1, 6, 0, 65, 42, 16, 0, 0xb                                              # Section "Code"
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
      run.call(11.1_f32, 22.2_f32).should eq 33.300003_f32
    end
  end
end
