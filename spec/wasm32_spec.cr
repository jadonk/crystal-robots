require "./spec_helper"
require "../src/battle/step_robot"
require "../src/battle/svg_replay"
require "../src/web/robot_api"

# `site/crystal-robots.wasm` is the browser build of `src/browser.cr`
# (Phase 5b-1): the tokenizer/parser, checker and WASM emitter (`crd_run`)
# and the interpreter (`crd_interpret`, a separate call -- see the module
# comment in `src/browser.cr`) compiled with
# `crystal build --target wasm32-unknown-wasi` and linked against the
# wasm32-wasi-libs sysroot (libc, libgc, libpcre2). These specs run it
# through `spec/support/wasm32_check.mjs`, which drives it via the real
# `site/wasi-shim.js`, and check its report against the native compiler
# on the same source.
describe "Browser build (wasm32-unknown-wasi)" do
  wasm32_it "round-trips examples/test.cr identically to the native CLI" do
    source = File.read("examples/test.cr")
    report = Browser32.run(source)

    report["problems"].as_a.should be_empty
    report["interpreter"]["status"].as_s.should eq "finished after 4 steps"
    report["interpreter"]["puts"].as_s.should eq "19"

    program = C::Parser.new(source).program
    report["derivation"].as_s.should eq program.derivation

    native_wasm = C.compile_to_wasm(source)
    report["wasm_len"].as_i.should eq native_wasm.size
  end

  wasm32_it "matches the checker and derivation on every example robot" do
    Dir.glob("examples/*.cr").sort.each do |file|
      source = File.read(file)
      report = Browser32.run(source)
      report["trapped"]?.should be_nil

      program = C::Parser.new(source).program
      expected_problems = C::Checker.check(program).map(&.to_s)
      report["problems"].as_a.map(&.as_s).should eq expected_problems
      report["derivation"].as_s.should eq program.derivation
    end
  end

  wasm32_it "traps cleanly on a parse error, without affecting the next call" do
    # Crystal 1.18.2 has no working `rescue` on `wasm32`: a parse error
    # traps the whole module instead of reporting gracefully (see the
    # module comment in `src/browser.cr`); what it printed before
    # trapping still reaches stderr.
    report = Browser32.run("this is not valid crystal-robots syntax {{{")
    report["trapped"].as_bool.should be_true
    report["stderr"].as_s.should contain "Unexpected character"

    # Each `Browser32.run` is a fresh module instance, so a trap never
    # affects the next call.
    ok = Browser32.run("puts 1")
    ok["problems"].as_a.should be_empty
  end

  # Phase 5b-2: `crd_battle_run` (`src/browser.cr`) runs a whole match --
  # `Battle::Field#run_stepwise`, `src/battle/step_robot.cr`'s non-fiber,
  # non-raising engine -- inside one module instance, interleaving 2 to 4
  # robots the way `bin/crystal-robots`' own matches do, at the same
  # per-cycle granularity `field.cr`'s fiber-based `run` uses, and renders
  # the same SVG SMIL replay (`Battle.svg_animation`,
  # `src/battle/svg_replay.cr`) the served `/battle` page does. `run` itself
  # is not the comparison target here: it depends on `spawn`/`Channel`,
  # untrusted on this build target (see `step_robot.cr`'s module comment),
  # so the ground truth is `run_stepwise` run natively -- the exact same
  # Crystal source `crd_battle_run` calls, compiled for the native target
  # instead of wasm32-unknown-wasi, the same cross-compilation-fidelity
  # comparison Phase 5b-1's own cases above make for `crd_run`/
  # `crd_interpret`. Same seed, same robots, same replay speed: the
  # standings and the rendered SVG text must match exactly.
  wasm32_it "runs a battle identically to the native interpreter engine" do
    sniper = File.read("examples/sniper.cr")
    rabbit = File.read("examples/rabbit.cr")
    seed = 3_u64
    limit = 40_000_i64
    cps = 300

    report = Browser32.battle([{"sniper", sniper}, {"rabbit", rabbit}], seed, limit, cps)
    report["trapped"]?.should be_nil

    native = CrystalRobots::Battle::Field.new([{"sniper", sniper}, {"rabbit", rabbit}], seed: seed, limit: limit).run_stepwise
    report["winner"].as_s?.should eq native.winner.try(&.name)
    report["cycles"].as_i64.should eq native.cycles
    report["robots"].as_a.map { |r| {r["name"].as_s, r["active"].as_bool, r["damage"].as_i, r["restarts"].as_i} }.should eq(
      native.robots.map { |r| {r.name, r.active, r.damage, r.restarts} }
    )
    report["svg"].as_s.should eq CrystalRobots::Battle.svg_animation(native, cps)
  end

  # A robot whose source fails to parse or check must not take the whole
  # match down with it: no `raise` on this target -- not even one rescued
  # in the very same function -- can be trusted not to trap the module
  # (Phase 5b-1's central finding, restated in `step_robot.cr`'s module
  # comment). It is reported inactive with its `error` instead, same as
  # `bin/crystal-robots`'s own matches and the served `/battle` page, and
  # the match still runs and picks a winner among the rest.
  wasm32_it "isolates a robot's parse error instead of trapping the whole match" do
    idle = File.read("examples/target.cr")
    report = Browser32.battle([{"bad", "if x\n"}, {"idle", idle}], 1_u64, 500_i64)
    report["trapped"]?.should be_nil

    bad_robot = report["robots"].as_a.find { |r| r["name"].as_s == "bad" }.not_nil!
    bad_robot["active"].as_bool.should be_false
    bad_robot["error"].as_s.should contain "Cannot reduce"
    report["winner"].as_s.should eq "idle"
  end

  # Phase 6: `site/cheat-sheet.json` (`scripts/build_cheat_sheet.cr`, a
  # `ci.cr --with-wasm32` step) is the file the editor's page fetches; it
  # must be byte-identical to `RobotAPI.cheat_sheet_json` computed fresh
  # right now, not just structurally similar -- otherwise a rebuild that
  # changes `ENTRIES` without re-running the generator would ship a stale
  # cheat-sheet next to the always-current served panel.
  wasm32_it "exports site/cheat-sheet.json identical to the panel's own data, right now" do
    File.read("site/cheat-sheet.json").should eq CrystalRobots::Web::RobotAPI.cheat_sheet_json
  end

  # Phase 6: the editor forks an example, the kid edits it, and it must
  # still check clean through the same non-raising path (`crd_check`,
  # `Browser.check`) the live-typing loop uses -- proof that an edited
  # example round-trips through the module, not just an untouched one.
  wasm32_it "checks an edited example clean through crd_check, not just the untouched original" do
    original = File.read("examples/sniper.cr")
    edited = original.sub("main(\"Sniper\")", "main(\"Sniper Junior\")") + "# edited by the editor's live-check spec\n"
    edited.should_not eq original

    report = Browser32.check(edited)
    report["trapped"]?.should be_nil
    report["error"].raw.should be_nil
    report["problems"].as_a.should be_empty

    program = C::Parser.new(edited).program
    report["passes"].as_i.should eq program.passes
    report["derivation"].as_s.should eq program.derivation
  end
end
