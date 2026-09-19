require "../spec_helper"

alias WikiRobots = CrystalRobots::Web::WikiRobots

# Reads the real fossil repository this checkout is running in, which
# already carries a mature `robot/*` wiki page for each of the five
# CROBOTS robots ported in earlier commits -- there is nothing to seed
# here, only to read back.
describe WikiRobots do
  it "lists the saved robots by name, without the robot/ prefix" do
    WikiRobots.names.should eq ["circler", "dodger", "hunter", "turret", "wallhugger"]
  end

  it "extracts a saved robot's fenced source" do
    source = WikiRobots.source("hunter")
    source.should_not be_nil
    source.not_nil!.should contain "def sweep"
  end

  it "returns nil for a name with no such wiki page" do
    WikiRobots.source("nope-not-a-robot").should be_nil
  end
end
