require "spec"

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
{% end %}

# Wraps a spec that needs the wasmer runtime.
macro wasmer_it(description, &block)
  {% if flag?(:wasmer) %}
    it({{description}}) {{block}}
  {% else %}
    pending({{description}} + " (run with -Dwasmer)")
  {% end %}
end
