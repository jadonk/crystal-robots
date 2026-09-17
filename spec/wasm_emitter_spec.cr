require "./spec_helper"
require "../src/compiler/wasm_emitter"

alias W = CrystalRobots::Compiler::WASM_Emitter

describe W do
  it "is the 8-byte magic header and version, nothing else" do
    W.minimal_module.should eq Bytes[0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]
  end
end
