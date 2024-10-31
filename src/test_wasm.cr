# https://glue.im/noah/introduction-to-webassembly-in-crystal
# https://github.com/naqvis/wasmer-crystal

require "wasmer"
require "crystal-robots"

compiler = CrystalRobots::Compiler.new
file = compiler.emitter

engine = Wasmer::Engine.new
store = Wasmer::Store.new(engine)

module_ = Wasmer::Module.new(store,file)

instance = Wasmer::Instance.new(module_)

run = instance.function("run").not_nil!

result = run.call(11.1, 22.2)

puts "Result from calling compiled WASM: #{result}"
