require "./spec_helper"

describe CrystalRobots do
  describe "Robot" do
  end

  describe "Compiler" do
    it "can be instantiated" do
      c = CrystalRobots::Compiler::Compiler.new
      c.should_not eq nil
    end
  end

  describe "Compiler::Tokenizer" do
    it "tokenizes single keyword" do
      t = CrystalRobots::Compiler::Tokenizer.new(" def")
      t.tokens.size.should eq 1
      t.tokens[0].type.should eq CrystalRobots::Compiler::Tokenizer::Type::DefKeyword
      t.tokens[0].index.should eq [1]
    end

    it "tokenizes single builtin" do
      t = CrystalRobots::Compiler::Tokenizer.new(" puts")
      t.tokens.size.should eq 1
      t.tokens[0].type.should eq CrystalRobots::Compiler::Tokenizer::Type::OneArgBuiltin
      t.tokens[0].index.should eq [1]
    end

    it "tokenizes single string" do
      t = CrystalRobots::Compiler::Tokenizer.new("  \"string\" ")
      t.tokens.size.should eq 1
      t.tokens[0].type.should eq CrystalRobots::Compiler::Tokenizer::Type::String
      t.tokens[0].index.should eq [2]
    end

    it "tokenizes builtin followed by string" do
      t = CrystalRobots::Compiler::Tokenizer.new(" puts \"string\"")
      t.tokens.size.should eq 2
      t.tokens[0].type.should eq CrystalRobots::Compiler::Tokenizer::Type::OneArgBuiltin
      t.tokens[0].index.should eq [1]
      t.tokens[0].value.should eq "puts"
      t.tokens[1].type.should eq CrystalRobots::Compiler::Tokenizer::Type::String
      t.tokens[1].index.should eq [6]
      t.tokens[1].value.should eq "\"string\""
    end

    it "tokenizes numbers" do
      t = CrystalRobots::Compiler::Tokenizer.new(" 32 \n  -11 39.5")
      t.tokens.size.should eq 3
      t.tokens[0].type.should eq CrystalRobots::Compiler::Tokenizer::Type::Number
      t.tokens[0].index.should eq [1]
      t.tokens[0].value.should eq "32"
      t.tokens[1].type.should eq CrystalRobots::Compiler::Tokenizer::Type::Number
      t.tokens[1].index.should eq [7]
      t.tokens[1].value.should eq "-11"
      t.tokens[2].type.should eq CrystalRobots::Compiler::Tokenizer::Type::Number
      t.tokens[2].index.should eq [11]
      t.tokens[2].value.should eq "39.5"
    end

    it "throws exception with bad keyword" do
      expect_raises(CrystalRobots::Compiler::Tokenizer::Error, "Unexpected token f") do
        t = CrystalRobots::Compiler::Tokenizer.new(" def foo")
      end
    end

    it "can produce token strings" do
      t = CrystalRobots::Compiler::Tokenizer.new(" puts \"string\"")
      t.to_s.should eq "∊🐍"
    end

    it "can recursively tokenize/parse" do
      t = CrystalRobots::Compiler::Tokenizer.new(" puts \"string\"")
      ast = t.parse
      s = t.to_array_s
      s.should eq ["∊🐍", "❤", "⏹"]
      "#{ast}".should eq "[[CrystalRobots::Compiler::Tokenizer::Token(@type=CrystalRobots::Compiler::Tokenizer::Type::OneArgBuiltin, @value=\"puts\", @index=[1]), CrystalRobots::Compiler::Tokenizer::Token(@type=CrystalRobots::Compiler::Tokenizer::Type::String, @value=\"\\\"string\\\"\", @index=[6])], [CrystalRobots::Compiler::Tokenizer::Token(@type=CrystalRobots::Compiler::Tokenizer::Type::OneArgStatement, @value=\"∊🐍\", @index=[0, 1])], [CrystalRobots::Compiler::Tokenizer::Token(@type=CrystalRobots::Compiler::Tokenizer::Type::Program, @value=\"❤\", @index=[0])]]"
    end
  end

  describe "Compiler::WASM_Emitter" do
    it "has an emitter" do
      c = CrystalRobots::Compiler::Compiler.new
      e = CrystalRobots::Compiler::WASM_Emitter.new(c.program)
      # https://webassembly.github.io/wabt/demo/wat2wasm/
      e.to_wasm.should eq Bytes[
        0, 0x61, 0x73, 0x6d,                        # WASM_BINARY_MAGIC
        1, 0, 0, 0,                                 # WASM_BINARY_VERSION
        1, 7, 1, 0x60, 2, 0x7d, 0x7d, 1, 0x7d,      # Section "Type"
        3, 2, 1, 0,                                 # Section "Function"
        7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 0,         # Section "Export"
        10, 9, 1, 7, 0, 0x20, 0, 0x20, 1, 0x92, 0xb # Section "Code"
      ]
    end

    it "test function should load the emited WASM" do
      c = CrystalRobots::Compiler::Compiler.new
      e = CrystalRobots::Compiler::WASM_Emitter.new(c.program)
      file = e.to_wasm
      i = load_wasm(file)
      i.should_not be_nil
    end

    it "test function should find exported function" do
      c = CrystalRobots::Compiler::Compiler.new
      e = CrystalRobots::Compiler::WASM_Emitter.new(c.program)
      file = e.to_wasm
      i = load_wasm(file)
      run = i.function("run")
      run.should_not be_nil
    end

    it "emitted function should run" do
      c = CrystalRobots::Compiler::Compiler.new
      e = CrystalRobots::Compiler::WASM_Emitter.new(c.program)
      file = e.to_wasm
      i = load_wasm(file)
      run = i.function("run").not_nil!
      run.call(11.1_f32, 22.2_f32).should eq 33.300003_f32
    end
  end
end
