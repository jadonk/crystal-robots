require "../spec_helper"

alias Capabilities = CrystalRobots::Web::Capabilities

describe Capabilities do
  it "grants read and run to a plain reader/runner" do
    Capabilities.can_read?("oi").should be_true
    Capabilities.can_run?("oi").should be_true
  end

  it "denies what a bare o (read) capability does not include" do
    Capabilities.can_read?("o").should be_true
    Capabilities.can_run?("o").should be_false
    Capabilities.can_read_wiki?("o").should be_false
  end

  it "expands u to oh (a reader can read, not run)" do
    Capabilities.can_read?("u").should be_true
    Capabilities.can_run?("u").should be_false
  end

  it "expands v to eoih (a developer can read and run)" do
    Capabilities.can_read?("v").should be_true
    Capabilities.can_run?("v").should be_true
  end

  it "grants everything to s (setup) and a (admin)" do
    Capabilities.can_read?("s").should be_true
    Capabilities.can_run?("s").should be_true
    Capabilities.can_read_wiki?("s").should be_true
    Capabilities.can_read?("a").should be_true
  end

  it "denies everything to an empty capability string" do
    Capabilities.can_read?("").should be_false
    Capabilities.can_run?("").should be_false
    Capabilities.can_read_wiki?("").should be_false
  end
end
