require "./spec_helper"
require "../src/version"

describe "crystal-robots CLI" do
  it "builds and reports its version" do
    output = `crystal run src/cli.cr -- --version`
    output.chomp.should eq "crystal-robots #{CrystalRobots::VERSION}"
  end

  it "-t prints the parse derivation for an example robot" do
    output = `crystal run src/cli.cr -- -t examples/hello.cr`
    output.should contain "∊№⏎"
    output.should contain "⏹"
  end
end
