# Generates `site/robots.json`: the example robots (`examples/*.cr`) the
# battle page's picker offers, bundled at build time so the static site
# needs no server to list them. Run by `ci.cr` under `--with-wasm32`,
# alongside `site/crystal-robots.wasm` -- both generated, both gitignored
# (`.fossil-settings/ignore-glob`).
#
#   crystal run scripts/build_robots_json.cr
require "json"

# `test.cr` is the wasm32 round-trip fixture (`puts 19`, no `main`, see
# `spec/wasm32_spec.cr`), not a fighting robot; every other example has a
# `main("Name") do ... end` fight loop and is a real battle entry.
descriptions = {
  "counter" => "Sweeps for rivals, fires, and moves when hit.",
  "rabbit"  => "Runs around the field without firing.",
  "rook"    => "Patrols straight lines and attacks nearby robots.",
  "sniper"  => "Finds a corner and scans for targets to shoot.",
  "target"  => "Stays still so you can practice aiming.",
}
robots = Dir.glob("examples/*.cr").sort.reject { |f| File.basename(f) == "test.cr" }.map do |file|
  name = File.basename(file, ".cr")
  {name: name, source: File.read(file), origin: "example", description: descriptions[name]}
end

Dir.glob("robots/*.md").sort.each do |file|
  markdown = File.read(file)
  blocks = markdown.scan(/```(?:crystal)?\s*\n(.*?)\n```/m)
  raise "expected one robot code block in #{file}" unless blocks.size == 1
  paragraph = markdown.split(/\n\s*\n/)[1].lines.map(&.strip).join(" ")
  robots << {name: File.basename(file, ".md"), source: blocks[0][1] + "\n", origin: "robot", description: paragraph}
end

File.write("site/robots.json", robots.to_json)
puts "site/robots.json: #{robots.size} robots (#{robots.map { |r| r[:name] }.join(", ")})"
