require "./spec_helper"

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
end
