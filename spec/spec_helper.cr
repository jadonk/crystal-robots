require "spec"
require "../src/compiler/program"
require "../src/compiler/parser"
require "../src/compiler/checker"
require "../src/compiler/interpreter"
require "../src/compiler/wasm_emitter"

# Parses and interprets `source` against a fresh `NullHost`, returning
# what it printed -- the same shape `run_puts` returns for the WASM path,
# so a spec can run one robot through both and compare.
def interpret_puts(source : String) : Array(Int32)
  program = CrystalRobots::Compiler::Parser.new(source).program
  host = CrystalRobots::Compiler::NullHost.new
  CrystalRobots::Compiler::Interpreter.execute(program, host)
  host.puts_out
end

# The wasmer runtime is optional. Specs that execute emitted WebAssembly
# compile only when the `wasmer` flag is set (`crystal spec -Dwasmer`) and
# are reported as pending otherwise, so plain `crystal spec` still gives a
# signal on a machine without libwasmer. Wasmer 4.4.0 is the last release
# with a linux-musl build; install it and `export WASMER_DIR=$HOME/.wasmer`
# before running with `-Dwasmer`.
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
{% end %}

# Wraps a spec that needs the wasmer runtime.
macro wasmer_it(description, &block)
  {% if flag?(:wasmer) %}
    it({{description}}) {{block}}
  {% else %}
    pending({{description}} + " (run with -Dwasmer)")
  {% end %}
end
