require "spec"
require "../src/compiler/program"
require "../src/compiler/parser"
require "../src/compiler/wasm_emitter"

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

  # Parses and compiles `source`, runs it under wasmer with `env.puts`
  # bound to a collector, and returns everything it printed.
  def run_puts(source : String) : Array(Int32)
    program = CrystalRobots::Compiler::Parser.new(source).program
    wasm = CrystalRobots::Compiler::WASM_Emitter.new(program).to_wasm
    engine = Wasmer::Engine.new
    store = Wasmer::Store.new(engine)
    module_ = Wasmer::Module.new(store, wasm)
    puts_out = [] of Int32
    puts_type = Wasmer::FunctionType.new(Wasmer.value_types(Wasmer::I32), Wasmer.value_types(Wasmer::I32))
    env = {"puts" => Wasmer::Function.new(store, type: puts_type) { |args|
      puts_out << args[0].as_i
      [Wasmer::Value.new(args[0].as_i)]
    }.as(Wasmer::WithExtern)}
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
