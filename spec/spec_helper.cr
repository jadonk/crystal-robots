require "spec"
require "../src/crystal-robots"
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