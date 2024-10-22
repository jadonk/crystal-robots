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
      c.emitter.should eq Bytes[0, 97, 115, 109, 1, 0, 0, 0]
    end
  end
end
