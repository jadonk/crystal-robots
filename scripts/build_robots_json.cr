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
robots = Dir.glob("examples/*.cr").sort.reject { |f| File.basename(f) == "test.cr" }.map do |file|
  {name: File.basename(file, ".cr"), source: File.read(file)}
end

File.write("site/robots.json", robots.to_json)
puts "site/robots.json: #{robots.size} robots (#{robots.map { |r| r[:name] }.join(", ")})"
