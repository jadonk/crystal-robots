require "./spec_helper"
require "json"

CHALLENGE_CHROMIUM_BIN = if (configured_bin = ENV["CHROMIUM_BIN"]?) && !configured_bin.empty?
                           Process.find_executable(configured_bin)
                         else
                           Process.find_executable("chromium") ||
                             Process.find_executable("chromium-browser") ||
                             Process.find_executable("google-chrome") ||
                             Process.find_executable("google-chrome-stable")
                         end

describe "site tournament and challenge (headless)" do
  if bin = CHALLENGE_CHROMIUM_BIN
    wasm32_it "runs a seeded tournament, replays a fight, passes level 1, and fits 360px" do
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run("node", ["spec/support/challenge_tournament_check.mjs", bin], output: output, error: errors)
      status.success?.should be_true, "challenge_tournament_check.mjs failed: #{output}\n#{errors}"
      JSON.parse(output.to_s)["ok"].as_bool.should be_true
    end
  else
    pending "tournament and challenge headless check (no browser found via CHROMIUM_BIN or chromium, chromium-browser, google-chrome, google-chrome-stable)"
  end
end
