require "./spec_helper"

alias W = CrystalRobots::Compiler::WASM_Emitter

describe W do
  it "is the 8-byte magic header and version at the start of every module" do
    W.minimal_module.should eq Bytes[0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]
  end

  wasmer_it "compiles and runs one puts statement" do
    run_puts("puts 42\n").should eq [42]
  end

  wasmer_it "compiles and runs several puts statements in order" do
    run_puts("puts 1\nputs 2\nputs 3\n").should eq [1, 2, 3]
  end
end
