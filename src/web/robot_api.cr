require "../compiler"
require "json"

# The robot API reference panel shown beside the editor on the parse and
# battle pages. `ENTRIES` is written by hand (a 10-year-old's wording can't
# be generated), but its *keys* are checked in spec against
# `Interpreter.builtin_names`, the interpreter's own dispatch table, so a
# builtin can never go undocumented and a documented name can never be
# make-believe.
module CrystalRobots::Web::RobotAPI
  record Entry, signature : String, returns : String, blurb : String, example : String, group : String

  # Order matters: this is the order the headings render in, kid-friendly
  # verb first.
  GROUPS = [
    "Sense — look around",
    "Move — get going",
    "Shoot — fire your cannon",
    "Math — work out the numbers",
    "Output — leave yourself a note",
  ]

  ENTRIES = {
    "scan" => Entry.new(
      signature: "scan(degree, resolution)",
      returns: "how far away the closest robot is, or 0 if there's nobody there",
      blurb: "Looks around with your scanner.",
      example: "range = scan(45, 10)",
      group: "Sense — look around"),
    "damage" => Entry.new(
      signature: "damage",
      returns: "how banged up you are, 0 (fine) to 99 (nearly done for)",
      blurb: "Checks how hurt you are.",
      example: "hurt = damage",
      group: "Sense — look around"),
    "speed" => Entry.new(
      signature: "speed",
      returns: "how fast you're going right now, 0 to 100",
      blurb: "Checks your current speed.",
      example: "going = speed",
      group: "Sense — look around"),
    "loc_x" => Entry.new(
      signature: "loc_x",
      returns: "where you are, left to right, 0 to 999",
      blurb: "Checks where you are on the field.",
      example: "x = loc_x",
      group: "Sense — look around"),
    "loc_y" => Entry.new(
      signature: "loc_y",
      returns: "where you are, bottom to top, 0 to 999",
      blurb: "Checks where you are on the field.",
      example: "y = loc_y",
      group: "Sense — look around"),
    "drive" => Entry.new(
      signature: "drive(degree, speed)",
      returns: "nothing useful",
      blurb: "Points you in a direction and starts your wheels.",
      example: "drive(90, 100)",
      group: "Move — get going"),
    "sleep" => Entry.new(
      signature: "sleep",
      returns: "nothing useful",
      blurb: "Waits one turn without doing anything else, so a drive keeps going.",
      example: "sleep",
      group: "Move — get going"),
    "cannon" => Entry.new(
      signature: "cannon(degree, range)",
      returns: "1 if a missile fired, or 0 if the cannon is still reloading",
      blurb: "Fires a missile in a direction, out to a distance.",
      example: "cannon(45, range)",
      group: "Shoot — fire your cannon"),
    "rand" => Entry.new(
      signature: "rand(limit)",
      returns: "a random whole number from 0 up to limit",
      blurb: "Picks a random number, like rolling dice.",
      example: "degree = rand(360)",
      group: "Math — work out the numbers"),
    "sqrt" => Entry.new(
      signature: "sqrt(number)",
      returns: "the square root of number",
      blurb: "Works out a square root.",
      example: "distance = sqrt(dx * dx + dy * dy)",
      group: "Math — work out the numbers"),
    "sin" => Entry.new(
      signature: "sin(degree)",
      returns: "the sine of the angle, scaled up by 100,000 so it's a whole number",
      blurb: "Works out the sine of an angle.",
      example: "y = sin(30)",
      group: "Math — work out the numbers"),
    "cos" => Entry.new(
      signature: "cos(degree)",
      returns: "the cosine of the angle, scaled up by 100,000 so it's a whole number",
      blurb: "Works out the cosine of an angle.",
      example: "x = cos(30)",
      group: "Math — work out the numbers"),
    "tan" => Entry.new(
      signature: "tan(degree)",
      returns: "the tangent of the angle, scaled up by 100,000 so it's a whole number",
      blurb: "Works out the tangent of an angle.",
      example: "slope = tan(30)",
      group: "Math — work out the numbers"),
    "atan" => Entry.new(
      signature: "atan(ratio)",
      returns: "an angle, -90 to 90, from a ratio scaled up by 100,000",
      blurb: "Turns a scaled-up ratio back into an angle.",
      example: "angle = atan(57735)",
      group: "Math — work out the numbers"),
    "puts" => Entry.new(
      signature: "puts(value)",
      returns: "nothing useful",
      blurb: "Writes down a number so you can see it later in the replay.",
      example: "puts damage",
      group: "Output — leave yourself a note"),
  } of String => Entry

  # A collapsible reference panel, `<details>`/`<summary>` only (Fossil's
  # CSP forbids inline script). `docs_href` is the page's own `link_base` +
  # `/docs`, so the panel links back to the full language reference
  # wherever the binary is mounted.
  def self.panel(docs_href : String) : String
    cost = CrystalRobots::Compiler::Interpreter::Costs.crobots.builtin
    String.build do |md|
      md << "<details class=\"robot-api\">\n"
      md << "<summary><strong>Robot API reference</strong> — what your robot can call</summary>\n\n"
      md << "<p>One line per call: what you type, what you get back, how many cycles it costs, and an example. "
      md << "See the <a href=\"#{docs_href}\">full language reference</a> for more.</p>\n\n"
      GROUPS.each do |group|
        md << "<details>\n<summary>#{group}</summary>\n\n<ul>\n"
        ENTRIES.each do |_name, e|
          next unless e.group == group
          md << "<li><a href=\"#{docs_href}\"><code>#{e.signature}</code></a> — "
          md << "#{e.blurb} Returns #{e.returns}. Costs #{cost} cycles. "
          md << "Example: <code>#{e.example}</code></li>\n"
        end
        md << "</ul>\n</details>\n\n"
      end
      md << "</details>\n\n"
    end
  end

  # The same `GROUPS`/`ENTRIES` the served panel above renders from,
  # exported as JSON for the browser editor's cheat-sheet (Phase 6): one
  # Crystal source of truth for both surfaces, never a second hand-kept
  # list. Written to `site/cheat-sheet.json` by
  # `scripts/build_cheat_sheet.cr`, a step inside `ci.cr --with-wasm32`
  # alongside `site/robots.json`; `spec/wasm32_spec.cr` checks the two stay
  # byte-identical.
  def self.cheat_sheet_json : String
    cost = CrystalRobots::Compiler::Interpreter::Costs.crobots.builtin
    {
      groups:  GROUPS,
      cost:    cost,
      entries: ENTRIES.map { |name, e|
        {name: name, signature: e.signature, returns: e.returns, blurb: e.blurb, example: e.example, group: e.group}
      },
    }.to_json
  end
end
