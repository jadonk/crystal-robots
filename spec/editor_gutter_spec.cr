require "./spec_helper"
require "json"

# Headless check for the `site/editor` line-number gutter (ticket
# 7a7758839e): the gutter must not soft-wrap independently of the
# textarea and must keep its scrollTop synced to the textarea's. Runs
# `spec/support/editor_gutter_check.mjs`, which drives a real headless
# Chromium over the DevTools protocol -- this machine has one at
# `chromium`/`chromium-browser`, but a machine without either reports
# this pending rather than failing the suite.
CHROMIUM_BIN = Process.find_executable("chromium") || Process.find_executable("chromium-browser")

describe "site/editor gutter (headless)" do
  if bin = CHROMIUM_BIN
    it "never soft-wraps a line and keeps the gutter's scrollTop synced to the textarea's" do
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run("node", ["spec/support/editor_gutter_check.mjs", bin], output: output, error: errors)
      status.success?.should be_true, "editor_gutter_check.mjs failed: #{output}\n#{errors}"
      report = JSON.parse(output.to_s)
      report["ok"].as_bool.should be_true
    end
  else
    pending "never soft-wraps a line and keeps the gutter's scrollTop synced to the textarea's (no chromium/chromium-browser binary on this machine)"
  end
end
