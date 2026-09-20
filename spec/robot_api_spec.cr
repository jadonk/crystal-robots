require "./spec_helper"
require "json"
require "../src/web/robot_api"

# `RobotAPI.cheat_sheet_json` (Phase 6) is the JSON export of the exact
# same `GROUPS`/`ENTRIES` the served `/parse` and `/battle` pages' panel
# (`RobotAPI.panel`) renders -- one Crystal source of truth for both
# surfaces, never a second hand-kept list. These specs check the export
# round-trips back to that same data, structurally; `wasm32_spec.cr`
# additionally checks the *generated file*, `site/cheat-sheet.json`
# (`scripts/build_cheat_sheet.cr`, a `ci.cr --with-wasm32` step), matches
# this export byte-for-byte.
describe CrystalRobots::Web::RobotAPI do
  it "exports every group, in the panel's own order" do
    sheet = JSON.parse(CrystalRobots::Web::RobotAPI.cheat_sheet_json)
    sheet["groups"].as_a.map(&.as_s).should eq CrystalRobots::Web::RobotAPI::GROUPS
  end

  it "exports the shared builtin cost the panel charges" do
    sheet = JSON.parse(CrystalRobots::Web::RobotAPI.cheat_sheet_json)
    sheet["cost"].as_i.should eq CrystalRobots::Compiler::Interpreter::Costs.crobots.builtin
  end

  it "exports every entry with exactly the panel's fields, keyed the same as ENTRIES" do
    sheet = JSON.parse(CrystalRobots::Web::RobotAPI.cheat_sheet_json)
    exported = sheet["entries"].as_a.map { |e|
      {e["name"].as_s, e["signature"].as_s, e["returns"].as_s, e["blurb"].as_s, e["example"].as_s, e["group"].as_s}
    }
    expected = CrystalRobots::Web::RobotAPI::ENTRIES.map { |name, e|
      {name, e.signature, e.returns, e.blurb, e.example, e.group}
    }.to_a
    exported.should eq expected
  end

  it "documents every builtin the interpreter table registers, not a hand-picked list" do
    registered = CrystalRobots::Compiler::Interpreter.builtin_names
    sheet = JSON.parse(CrystalRobots::Web::RobotAPI.cheat_sheet_json)
    sheet["entries"].as_a.map { |e| e["name"].as_s }.sort.should eq registered.sort
  end
end
