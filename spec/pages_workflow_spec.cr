require "./spec_helper"
require "yaml"

# .github/workflows/pages.yml is not Crystal code, so there is nothing
# for `crystal spec` to run against it directly; this instead parses
# it with the stdlib (`require "yaml"`, backed by libyaml, present in
# this environment -- confirmed directly, no external tool needed) and
# pins its trigger and step order, so a future edit cannot silently
# change what the deploy publishes or when.
#
# YAML 1.1's bareword booleans bite here: an unquoted `on:` key parses
# as the boolean `true`, not the string "on" -- `doc[true]`, not
# `doc["on"]`, is genuinely how this reads back.
describe ".github/workflows/pages.yml" do
  workflow = YAML.parse(File.read(".github/workflows/pages.yml"))

  it "triggers only on a push to main or dev (YAML 1.1 parses the bare `on:` key as true, not \"on\")" do
    workflow[true]["push"]["branches"].as_a.map(&.as_s).should eq ["main", "dev"]
  end

  it "also allows a manual dispatch" do
    workflow[true].as_h.keys.map(&.as_s).should contain "workflow_dispatch"
  end

  it "runs the build steps in order: checkout, install Crystal, apt lld, ci.sh --with-wasm32, upload the Pages artifact" do
    steps = workflow["jobs"]["build"]["steps"].as_a
    identifiers = steps.map do |s|
      h = s.as_h
      h["uses"]?.try(&.as_s) || h["run"]?.try(&.as_s) || raise "step has neither uses nor run: #{s}"
    end
    identifiers.should eq [
      "actions/checkout@v4",
      "oprypin/install-crystal@v1",
      "sudo apt-get update && sudo apt-get install -y lld",
      "scripts/ci.sh --with-wasm32",
      "actions/upload-pages-artifact@v3",
    ]
  end

  it "pins the installed Crystal version to what this environment itself runs" do
    steps = workflow["jobs"]["build"]["steps"].as_a
    install_step = steps.find { |s| s.as_h["uses"]?.try(&.as_s) == "oprypin/install-crystal@v1" }.not_nil!
    install_step["with"]["crystal"].as_s.should eq "1.18.2"
  end

  it "deploys what build uploaded, needing the build job first" do
    workflow["jobs"]["deploy"]["needs"].as_s.should eq "build"
  end
end
