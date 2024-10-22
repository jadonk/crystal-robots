require "spec"
require "../src/crystal-robots.cr"

describe CrystalRobots do
  describe "Emitter" do
    it "can be instantiated" do
      c = CrystalRobots::Emitter.new
      c.should_not eq nil
    end

    it "has an emitter" do
      c = CrystalRobots::Emitter.new
      # https://webassembly.github.io/wabt/demo/wat2wasm/
      c.emitter.should eq Bytes[
        0,0x61,0x73,0x6d,                  # WASM_BINARY_MAGIC
        1,0,0,0,                           # WASM_BINARY_VERSION
      ]
    end
  end
end
