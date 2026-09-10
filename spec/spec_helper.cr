require "spec"
require "../src/crystal-robots"
require "semantic_version"

# The wasmer runtime is optional. Specs that execute emitted WebAssembly
# compile only when the `wasmer` flag is set (`crystal spec -Dwasmer`) and
# are reported as pending otherwise, so `crystal spec` gives a signal on a
# machine without libwasmer. Wasmer 4.4.0 is the last release with a
# linux-musl build; install it with `scripts/install_wasmer.sh v4.4.0` and
# export WASMER_DIR=$HOME/.wasmer before running the specs.
{% if flag?(:wasmer) %}
  require "wasmer"

  class WASMSpec
    getter last_puts : String

    def initialize(@last_puts)
    end

    # https://github.com/naqvis/wasmer-crystal
    def load_wasm(file)
      engine = Wasmer::Engine.new
      store = Wasmer::Store.new(engine)
      module_ = Wasmer::Module.new(store, file)
      imports = Wasmer::ImportObject.new
      params = Wasmer.value_types(Wasmer::I32)
      results = Wasmer.value_types(Wasmer::I32)
      oneArgStatement = Wasmer::FunctionType.new(params, results)
      wasm_puts_import = Wasmer::Function.new(store, type: oneArgStatement, &->wasm_puts(Array(Wasmer::Value)))
      imports.register("env", {"puts" => wasm_puts_import.as(Wasmer::WithExtern)})
      Wasmer::Instance.new(module_, imports)
    end

    def wasm_puts(args : Array(Wasmer::Value)) : Array(Wasmer::Value)
      @last_puts = "#{args[0].as_i}"
      [Wasmer::Value.new(0)]
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
