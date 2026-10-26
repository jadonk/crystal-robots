require "./spec_helper"
require "json"

LANDING_CHROMIUM_BIN = if (configured_bin = ENV["CHROMIUM_BIN"]?) && !configured_bin.empty?
                         Process.find_executable(configured_bin)
                       else
                         Process.find_executable("chromium") ||
                           Process.find_executable("chromium-browser") ||
                           Process.find_executable("google-chrome") ||
                           Process.find_executable("google-chrome-stable")
                       end

describe "site landing (headless)" do
  if bin = LANDING_CHROMIUM_BIN
    wasm32_it "mounts the battle, opens all five layers, and fits 360px" do
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run("node", ["spec/support/landing_check.mjs", bin], output: output, error: errors)
      status.success?.should be_true, "landing_check.mjs failed: #{output}\n#{errors}"
      JSON.parse(output.to_s)["ok"].as_bool.should be_true
    end
  else
    pending "mounts the battle, opens all five layers, and fits 360px (no browser found via CHROMIUM_BIN or chromium, chromium-browser, google-chrome, google-chrome-stable)"
  end
end
