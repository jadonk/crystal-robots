require "spec"
require "../src/compiler/program"
require "../src/compiler/parser"
require "../src/compiler/checker"
require "../src/compiler/interpreter"
require "../src/compiler/wasm_emitter"
require "../src/battle/field"
require "../src/battle/robot_host"
require "../src/battle/match"
require "../src/tournament/tournament"
require "../src/web/app"

alias BattleField = CrystalRobots::Battle::Field

# Parses and interprets `source` against a fresh `NullHost`, returning
# what it printed -- the same shape `run_puts` returns for the WASM path,
# so a spec can run one robot through both and compare.
def interpret_puts(source : String) : Array(Int32)
  program = CrystalRobots::Compiler::Parser.new(source).program
  host = CrystalRobots::Compiler::NullHost.new
  CrystalRobots::Compiler::Interpreter.execute(program, host)
  host.puts_out
end

# Interprets `source` with cycle accounting on, returning the total charged.
def interpret_cycles(source : String, costs = CrystalRobots::Compiler::Interpreter::Costs.new) : Int64
  program = CrystalRobots::Compiler::Parser.new(source).program
  CrystalRobots::Compiler::Interpreter.execute(program, CrystalRobots::Compiler::NullHost.new, costs)
end

# The wasmer runtime is optional. Specs that execute emitted WebAssembly
# compile only when the `wasmer` flag is set (`crystal spec -Dwasmer`) and
# are reported as pending otherwise, so plain `crystal spec` still gives a
# signal on a machine without libwasmer. Wasmer 4.4.0 is the last release
# with a linux-musl build; install it and `export WASMER_DIR=$HOME/.wasmer`
# before running with `-Dwasmer`.
#
# Also `export GC_DONT_GC=1` for that run: past roughly a hundred examples
# that each create their own `Wasmer::Engine`/`Store`/`Function` closures,
# Boehm GC's finalizer thread occasionally races the wasmer-crystal shard's
# native cleanup (`fatal runtime error: Rust cannot catch foreign
# exceptions`, or a bare segfault) -- reproducible with the grammar
# entirely unrelated to which spec happens to trip it. Disabling
# collection for the run's short lifetime (a spec process exits in
# seconds) sidesteps the race instead of chasing it in a shard this
# project does not own.
{% if flag?(:wasmer) %}
  require "wasmer"

  # Instantiates an emitted module with no host imports to bind.
  def instantiate(wasm : Bytes) : Wasmer::Instance
    engine = Wasmer::Engine.new
    store = Wasmer::Store.new(engine)
    module_ = Wasmer::Module.new(store, wasm)
    Wasmer::Instance.new(module_, Wasmer::ImportObject.new)
  end

  # A stand-in host for the builtins that have no real implementation yet
  # (there is no battlefield or interpreter behind them until a later
  # commit): the sensors return fixed, distinct values so a spec can check
  # the right one was called, and the two-argument builtins return the sum
  # of their arguments so a spec can check both arguments made it through
  # in order. `rand sqrt sin cos tan atan` do their actual math, since that
  # much needs no host at all.
  STUB_SENSORS = {"damage" => 11, "speed" => 22, "loc_x" => 33, "loc_y" => 44, "sleep" => 55}

  # Parses and compiles `source`, runs it under wasmer with every builtin
  # bound (`env.puts` to a collector, the rest to the stand-in host above),
  # and returns everything `puts` printed.
  def run_puts(source : String) : Array(Int32)
    program = CrystalRobots::Compiler::Parser.new(source).program
    wasm = CrystalRobots::Compiler::WASM_Emitter.new(program).to_wasm
    engine = Wasmer::Engine.new
    store = Wasmer::Store.new(engine)
    module_ = Wasmer::Module.new(store, wasm)
    puts_out = [] of Int32
    t0 = Wasmer::FunctionType.new(Wasmer.value_types, Wasmer.value_types(Wasmer::I32))
    t1 = Wasmer::FunctionType.new(Wasmer.value_types(Wasmer::I32), Wasmer.value_types(Wasmer::I32))
    t2 = Wasmer::FunctionType.new(Wasmer.value_types(Wasmer::I32, Wasmer::I32), Wasmer.value_types(Wasmer::I32))
    fn1 = ->(block : Int32 -> Int32) {
      Wasmer::Function.new(store, type: t1) { |a| [Wasmer::Value.new(block.call(a[0].as_i))] }.as(Wasmer::WithExtern)
    }
    env = {} of String => Wasmer::WithExtern
    env["puts"] = fn1.call(->(n : Int32) { puts_out << n; n })
    STUB_SENSORS.each { |name, value| env[name] = Wasmer::Function.new(store, type: t0) { [Wasmer::Value.new(value)] }.as(Wasmer::WithExtern) }
    {"scan", "cannon", "drive"}.each do |name|
      env[name] = Wasmer::Function.new(store, type: t2) { |a| [Wasmer::Value.new(a[0].as_i + a[1].as_i)] }.as(Wasmer::WithExtern)
    end
    env["rand"] = fn1.call(->(n : Int32) { n })
    env["sqrt"] = fn1.call(->(n : Int32) { Math.sqrt(n).to_i32 })
    env["sin"] = fn1.call(->(n : Int32) { Math.sin(n.to_f * Math::PI / 180).round.to_i32 })
    env["cos"] = fn1.call(->(n : Int32) { Math.cos(n.to_f * Math::PI / 180).round.to_i32 })
    env["tan"] = fn1.call(->(n : Int32) { Math.tan(n.to_f * Math::PI / 180).round.to_i32 })
    env["atan"] = fn1.call(->(n : Int32) { (Math.atan(n.to_f) * 180 / Math::PI).round.to_i32 })
    imports = Wasmer::ImportObject.new
    imports.register("env", env)
    instance = Wasmer::Instance.new(module_, imports)
    instance.function("run").not_nil!.call
    puts_out
  end

  # Like `run_puts`, but also binds `env.tick` (present only when `costs`
  # is given to `WASM_Emitter.new`) to an accumulator, so a spec can
  # check the module's total charged cycles against the interpreter's.
  def run_with_ticks(source : String, costs : CrystalRobots::Compiler::Interpreter::Costs) : {Array(Int32), Int64}
    program = CrystalRobots::Compiler::Parser.new(source).program
    wasm = CrystalRobots::Compiler::WASM_Emitter.new(program, costs).to_wasm
    engine = Wasmer::Engine.new
    store = Wasmer::Store.new(engine)
    module_ = Wasmer::Module.new(store, wasm)
    puts_out = [] of Int32
    ticks = 0_i64
    t0 = Wasmer::FunctionType.new(Wasmer.value_types, Wasmer.value_types(Wasmer::I32))
    t1 = Wasmer::FunctionType.new(Wasmer.value_types(Wasmer::I32), Wasmer.value_types(Wasmer::I32))
    t2 = Wasmer::FunctionType.new(Wasmer.value_types(Wasmer::I32, Wasmer::I32), Wasmer.value_types(Wasmer::I32))
    fn1 = ->(block : Int32 -> Int32) {
      Wasmer::Function.new(store, type: t1) { |a| [Wasmer::Value.new(block.call(a[0].as_i))] }.as(Wasmer::WithExtern)
    }
    env = {} of String => Wasmer::WithExtern
    env["tick"] = fn1.call(->(n : Int32) { ticks += n; n })
    env["puts"] = fn1.call(->(n : Int32) { puts_out << n; n })
    STUB_SENSORS.each { |name, value| env[name] = Wasmer::Function.new(store, type: t0) { [Wasmer::Value.new(value)] }.as(Wasmer::WithExtern) }
    {"scan", "cannon", "drive"}.each do |name|
      env[name] = Wasmer::Function.new(store, type: t2) { |a| [Wasmer::Value.new(a[0].as_i + a[1].as_i)] }.as(Wasmer::WithExtern)
    end
    env["rand"] = fn1.call(->(n : Int32) { n })
    env["sqrt"] = fn1.call(->(n : Int32) { Math.sqrt(n).to_i32 })
    env["sin"] = fn1.call(->(n : Int32) { Math.sin(n.to_f * Math::PI / 180).round.to_i32 })
    env["cos"] = fn1.call(->(n : Int32) { Math.cos(n.to_f * Math::PI / 180).round.to_i32 })
    env["tan"] = fn1.call(->(n : Int32) { Math.tan(n.to_f * Math::PI / 180).round.to_i32 })
    env["atan"] = fn1.call(->(n : Int32) { (Math.atan(n.to_f) * 180 / Math::PI).round.to_i32 })
    imports = Wasmer::ImportObject.new
    imports.register("env", env)
    instance = Wasmer::Instance.new(module_, imports)
    instance.function("run").not_nil!.call
    {puts_out, ticks}
  end
{% end %}

# Wraps a spec that needs the wasmer runtime.
macro wasmer_it(description, &block)
  {% if flag?(:wasmer) %}
    it({{description}}) {{block}}
  {% else %}
    pending({{description}} + " (run with -Dwasmer)")
  {% end %}
end

# The browser build (`crystal build --target wasm32-unknown-wasi
# src/browser.cr`) is optional the same way wasmer is: specs that load
# it compile only under `-Dcrd_wasm32` (`crystal spec -Dcrd_wasm32`)
# and need `crystal run ci.cr -- --with-wasm32` to have built
# `site/crystal-robots.wasm` first; otherwise they are pending, not a
# link failure or a tolerated skip.
#
# Driving the module is delegated to `node spec/support/wasm32_check.mjs`,
# which runs it through the real `site/wasi-shim.js` -- the exact code
# the browser page loads, not a second WASI implementation that could
# drift out of sync. The wasmer Crystal shard (0.2.3, already used for
# the native-WASM specs above) was tried first for this too: its
# `Wasmer::Wasi` layer segfaults inside `wasi_env_new` after a handful
# of calls, reproducible outside this project's own code, so this spec
# does not depend on wasmer at all.
{% if flag?(:crd_wasm32) %}
  require "json"

  module Browser32
    MODULE_PATH  = "site/crystal-robots.wasm"
    CHECK_SCRIPT = "spec/support/wasm32_check.mjs"

    # Runs `source` through every pass in a temp file and returns the
    # parsed JSON report `crd_run` builds (see `src/browser.cr`), via
    # `spec/support/wasm32_check.mjs`.
    def self.run(source : String) : JSON::Any
      file = File.tempfile("crd-wasm32", ".cr")
      begin
        file.print(source)
        file.flush
        output = IO::Memory.new
        status = Process.run("node", [CHECK_SCRIPT, MODULE_PATH, file.path], output: output, error: STDERR)
        raise "node #{CHECK_SCRIPT} exited #{status.exit_code}" unless status.success?
        JSON.parse(output.to_s)
      ensure
        file.delete
      end
    end
  end
{% end %}

macro wasm32_it(description, &block)
  {% if flag?(:crd_wasm32) %}
    it({{description}}) {{block}}
  {% else %}
    pending({{description}} + " (run with -Dcrd_wasm32 after crystal run ci.cr -- --with-wasm32)")
  {% end %}
end
