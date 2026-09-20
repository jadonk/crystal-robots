# Generates `site/cheat-sheet.json`: the browser editor's (Phase 6)
# consolidated cheat-sheet, exported straight from `RobotAPI::GROUPS`/
# `ENTRIES` (`src/web/robot_api.cr`) -- the same data the served `/parse`
# and `/battle` pages' "Robot API reference" panel renders -- so the two
# surfaces can never drift apart. Run by `ci.cr` under `--with-wasm32`,
# alongside `site/robots.json` -- both generated, both gitignored
# (`.fossil-settings/ignore-glob`).
#
#   crystal run scripts/build_cheat_sheet.cr
require "../src/web/robot_api"

File.write("site/cheat-sheet.json", CrystalRobots::Web::RobotAPI.cheat_sheet_json)
puts "site/cheat-sheet.json: #{CrystalRobots::Web::RobotAPI::ENTRIES.size} entries in #{CrystalRobots::Web::RobotAPI::GROUPS.size} groups"
