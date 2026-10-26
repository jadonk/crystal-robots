require "./spec_helper"
require "json"

describe "challenge checks against real battles" do
  wasm32_it "has pass and fail cases for levels 1 through 4" do
    output = IO::Memory.new
    errors = IO::Memory.new
    status = Process.run("node", ["spec/support/challenge_checks_check.mjs"], output: output, error: errors)
    status.success?.should be_true, "challenge_checks_check.mjs failed: #{output}\n#{errors}"
    JSON.parse(output.to_s)["ok"].as_bool.should be_true
  end
end
