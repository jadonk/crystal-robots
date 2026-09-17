require "./spec_helper"
require "../src/version"

describe "crystal-robots CLI" do
  it "builds and reports its version" do
    output = `crystal run src/cli.cr -- --version`
    output.chomp.should eq "crystal-robots #{CrystalRobots::VERSION}"
  end
end
