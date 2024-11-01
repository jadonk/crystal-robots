require "spec"
require "../src/crystal-robots"
require "wasmer"

# https://github.com/naqvis/wasmer-crystal
def load_wasm(file)
  engine = Wasmer::Engine.new
  store = Wasmer::Store.new(engine)
  module_ = Wasmer::Module.new(store, file)
  Wasmer::Instance.new(module_)
end
