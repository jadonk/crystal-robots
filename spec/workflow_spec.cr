require "./spec_helper"
require "yaml"

# The Pages workflow has been fixed twice by hand-reading YAML (trigger
# branches, then the lld step) with each gate independently re-parsing it
# outside the project. Pin its shape here with Crystal's own stdlib YAML
# instead, no outside parser.
describe ".github/workflows/pages.yml" do
  workflow = YAML.parse(File.read(".github/workflows/pages.yml"))

  it "triggers on push to main and dev" do
    # YAML 1.1 parses the unquoted `on:` key as the boolean `true`.
    branches = workflow[true]["push"]["branches"].as_a.map(&.as_s)
    branches.should eq(["main", "dev"])
  end

  it "runs the build job before the deploy job" do
    workflow["jobs"].as_h.keys.should eq(["build", "deploy"])
  end

  it "builds the browser compiler in the exact expected step order" do
    steps = workflow["jobs"]["build"]["steps"].as_a
    steps[0]["uses"].as_s.should eq("actions/checkout@v4")

    steps[1]["uses"].as_s.should eq("oprypin/install-crystal@v1")
    steps[1]["with"]["crystal"].as_s.should eq("1.18.2")

    steps[2]["run"].as_s.should eq("sudo apt-get update && sudo apt-get install -y lld")

    steps[3]["run"].as_s.should eq("crystal run ci.cr -- --with-wasm32")

    steps[4]["uses"].as_s.should eq("actions/upload-pages-artifact@v3")
  end

  it "deploys with actions/deploy-pages under the github-pages environment" do
    deploy = workflow["jobs"]["deploy"]
    deploy["environment"]["name"].as_s.should eq("github-pages")
    deploy["steps"].as_a.map(&.["uses"].as_s).should eq(["actions/deploy-pages@v4"])
  end
end
