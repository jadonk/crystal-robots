require "./spec_helper"

{% if flag?(:crd_wasm32) %}
  describe "browser compiled robots" do
    it "matches interpreted battles and a full tournament, falls back per robot, and stays within the timing budget" do
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run("node", ["spec/support/wasm32_compiled_check.mjs", "site/crystal-robots.wasm"], output: output, error: errors)
      status.success?.should be_true, "wasm32_compiled_check.mjs failed: #{output}\n#{errors}"
      result = JSON.parse(output.to_s)
      result["ok"].as_bool.should be_true
      puts "compiled #{result["milliseconds"]["compiled"]} ms; interpreter #{result["milliseconds"]["interpreter"]} ms for the 4-robot 60,000-cycle battle"
    end
  end
{% end %}
