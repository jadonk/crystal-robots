require "./spec_helper"

describe "site/wasm-view.js" do
  if Process.find_executable("node")
    it "decodes a native counter module into sections and known instructions" do
      bytes = C.compile_to_wasm(File.read("examples/counter.cr"))
      file = File.tempfile("crd-counter", ".wasm")
      begin
        file.write(bytes)
        file.flush
        output = IO::Memory.new
        errors = IO::Memory.new
        status = Process.run("node", ["spec/support/wasm_view_check.mjs", file.path], output: output, error: errors)
        status.success?.should be_true, "wasm_view_check.mjs failed: #{output}\n#{errors}"
        JSON.parse(output.to_s)["ok"].as_bool.should be_true
      ensure
        file.delete
      end
    end
  else
    pending "decodes a native counter module into sections and known instructions (no node binary on this machine)"
  end
end
