require "spec"
require "../src/crystal-robots"
require "semantic_version"

alias C = CrystalRobots::Compiler

# The wasmer runtime is optional. Specs that execute emitted WebAssembly
# compile only when the `wasmer` flag is set (`crystal spec -Dwasmer`) and
# are reported as pending otherwise, so `crystal spec` gives a signal on a
# machine without libwasmer. Wasmer 4.4.0 is the last release with a
# linux-musl build; install it with `scripts/install_wasmer.sh v4.4.0` and
# export WASMER_DIR=$HOME/.wasmer before running the specs.
{% if flag?(:wasmer) %}
  require "wasmer"

  # Runs an emitted module under wasmer with every builtin bound to a
  # `Compiler::Host`, the same interface the interpreter uses.
  class WASMSpec
    getter last_puts : String
    getter puts_out = [] of String
    getter host : CrystalRobots::Compiler::Host
    getter ticks = 0_i64

    def initialize(@last_puts = "", @host = CrystalRobots::Compiler::NullHost.new)
    end

    # https://github.com/naqvis/wasmer-crystal
    def load_wasm(file)
      engine = Wasmer::Engine.new
      store = Wasmer::Store.new(engine)
      module_ = Wasmer::Module.new(store, file)
      imports = Wasmer::ImportObject.new
      i32 = Wasmer.value_types(Wasmer::I32)
      none = Wasmer.value_types
      two = Wasmer.value_types(Wasmer::I32, Wasmer::I32)
      t0 = Wasmer::FunctionType.new(none, i32)
      t1 = Wasmer::FunctionType.new(i32, i32)
      t2 = Wasmer::FunctionType.new(two, i32)
      h = @host
      env = {} of String => Wasmer::WithExtern
      env["puts"] = Wasmer::Function.new(store, type: t1, &->wasm_puts(Array(Wasmer::Value)))
      env["tick"] = fn(store, t1) { |a| @ticks += a[0].as_i; 0 }
      env["scan"] = fn(store, t2) { |a| h.scan(a[0].as_i, a[1].as_i) }
      env["cannon"] = fn(store, t2) { |a| h.cannon(a[0].as_i, a[1].as_i) }
      env["drive"] = fn(store, t2) { |a| h.drive(a[0].as_i, a[1].as_i) }
      env["damage"] = fn(store, t0) { |_| h.damage }
      env["speed"] = fn(store, t0) { |_| h.speed }
      env["loc_x"] = fn(store, t0) { |_| h.loc_x }
      env["loc_y"] = fn(store, t0) { |_| h.loc_y }
      env["sleep"] = fn(store, t0) { |_| h.sleep }
      env["rand"] = fn(store, t1) { |a| h.rand(a[0].as_i) }
      env["sqrt"] = fn(store, t1) { |a| h.sqrt(a[0].as_i) }
      env["sin"] = fn(store, t1) { |a| h.sin(a[0].as_i) }
      env["cos"] = fn(store, t1) { |a| h.cos(a[0].as_i) }
      env["tan"] = fn(store, t1) { |a| h.tan(a[0].as_i) }
      env["atan"] = fn(store, t1) { |a| h.atan(a[0].as_i) }
      imports.register("env", env)
      Wasmer::Instance.new(module_, imports)
    end

    private def fn(store, type, &block : Array(Wasmer::Value) -> Int32) : Wasmer::WithExtern
      Wasmer::Function.new(store, type: type) { |args| [Wasmer::Value.new(block.call(args))] }.as(Wasmer::WithExtern)
    end

    def wasm_puts(args : Array(Wasmer::Value)) : Array(Wasmer::Value)
      @last_puts = "#{args[0].as_i}"
      @puts_out << @last_puts
      @host.puts(args[0].as_i)
      [Wasmer::Value.new(0)]
    end

    # Compile and run `source`; returns everything it printed. With `costs`
    # the module carries cycle accounting and `ticks` totals it.
    def run(source : String, costs : CrystalRobots::Compiler::Interpreter::Costs? = nil) : Array(String)
      program = CrystalRobots::Compiler::Parser.new(source).program
      i = load_wasm(CrystalRobots::Compiler::WASM_Emitter.new(program, costs).to_wasm)
      i.function("run").not_nil!.call
      @puts_out
    end
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
