require "./spec_helper"

describe Crystal::Robots do
  describe "Compiler" do
    it "can be instantiated" do
      c = Crystal::Robots::Compiler.new
      c.should_not eq nil
    end

    it "tokenizes single keyword" do
      c = Crystal::Robots::Compiler.new
      tokens = c.tokenizer(" def")
      tokens.size.should eq 1
      tokens[0].type.should eq Crystal::Robots::Compiler::TokenType::Keyword
    end

    it "throws exception with bad keyword" do
      c = Crystal::Robots::Compiler.new
      expect_raises(Crystal::Robots::Compiler::TokenizerError, "Unexpected token f") do
        tokens = c.tokenizer(" def foo")
      end
    end

    it "has an emitter" do
      c = Crystal::Robots::Compiler.new
      # https://webassembly.github.io/wabt/demo/wat2wasm/
      c.emitter.should eq Bytes[
        0, 0x61, 0x73, 0x6d,                        # WASM_BINARY_MAGIC
        1, 0, 0, 0,                                 # WASM_BINARY_VERSION
        1, 7, 1, 0x60, 2, 0x7d, 0x7d, 1, 0x7d,      # Section "Type"
        3, 2, 1, 0,                                 # Section "Function"
        7, 7, 1, 3, 0x72, 0x75, 0x6e, 0, 0,         # Section "Export"
        10, 9, 1, 7, 0, 0x20, 0, 0x20, 1, 0x92, 0xb # Section "Code"
      ]
    end
  end
end
