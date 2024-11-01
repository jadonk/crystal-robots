require "./spec_helper"

describe CrystalRobots do
  describe "Robot" do
  end

  describe "Compiler" do
    it "can be instantiated" do
      c = CrystalRobots::Compiler.new
      c.should_not eq nil
    end

    it "tokenizes single keyword" do
      c = CrystalRobots::Compiler.new
      tokens = c.tokenize(" def")
      tokens.size.should eq 1
      tokens[0].type.should eq CrystalRobots::Compiler::TokenType::Keyword
    end

    it "tokenizes single builtin" do
      c = CrystalRobots::Compiler.new
      tokens = c.tokenize(" puts")
      tokens.size.should eq 1
      tokens[0].type.should eq CrystalRobots::Compiler::TokenType::Builtin
    end

    it "tokenizes single string" do
      c = CrystalRobots::Compiler.new
      tokens = c.tokenize(" \"string\"")
      tokens.size.should eq 1
      tokens[0].type.should eq CrystalRobots::Compiler::TokenType::String
    end

    it "tokenizes builtin followed by string" do
      c = CrystalRobots::Compiler.new
      tokens = c.tokenize(" puts \"string\"")
      tokens.size.should eq 2
      tokens[0].type.should eq CrystalRobots::Compiler::TokenType::Builtin
      tokens[1].type.should eq CrystalRobots::Compiler::TokenType::String
    end

    it "throws exception with bad keyword" do
      c = CrystalRobots::Compiler.new
      expect_raises(CrystalRobots::Compiler::TokenizerError, "Unexpected token f") do
        tokens = c.tokenize(" def foo")
      end
    end

    it "has an emitter" do
      c = CrystalRobots::Compiler.new
      # https://webassembly.github.io/wabt/demo/wat2wasm/
      c.emitter(c.program).should eq Bytes[
        0, 0x61, 0x73, 0x6d,                        # WASM_BINARY_MAGIC
        1, 0, 0, 0,                                 # WASM_BINARY_VERSION
        1, 7, 1, 0x60, 2, 0x7d, 0x7d, 1, 0x7d,      # Section "Type"
        3, 2, 1, 0,                                 # Section "Function"
        7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 0,         # Section "Export"
        10, 9, 1, 7, 0, 0x20, 0, 0x20, 1, 0x92, 0xb # Section "Code"
      ]
    end

    it "test function should load the emited WASM" do
      c = CrystalRobots::Compiler.new
      file = c.emitter(c.program)
      i = load_wasm(file)
      i.should_not be_nil
    end

    it "test function should find exported function" do
      c = CrystalRobots::Compiler.new
      file = c.emitter(c.program)
      i = load_wasm(file)
      run = i.function("run")
      run.should_not be_nil
    end

    it "emitted function should run" do
      c = CrystalRobots::Compiler.new
      file = c.emitter(c.program)
      i = load_wasm(file)
      run = i.function("run").not_nil!
      run.call(11.1_f32, 22.2_f32).should eq 33.300003_f32
    end
  end
end
