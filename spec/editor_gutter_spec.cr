require "./spec_helper"
require "json"

# Headless check for the `site/editor` line-number gutter (ticket
# 7a7758839e): the gutter must not soft-wrap independently of the
# textarea and must keep its scrollTop synced to the textarea's. Runs
# `spec/support/editor_gutter_check.mjs`, which drives a real headless
# Chromium over the DevTools protocol. CHROMIUM_BIN can select a specific
# binary; otherwise try chromium, chromium-browser, google-chrome, then
# google-chrome-stable. A machine without a usable binary reports pending.
CHROMIUM_BIN = if (configured_bin = ENV["CHROMIUM_BIN"]?) && !configured_bin.empty?
                 Process.find_executable(configured_bin)
               else
                 Process.find_executable("chromium") ||
                   Process.find_executable("chromium-browser") ||
                   Process.find_executable("google-chrome") ||
                   Process.find_executable("google-chrome-stable")
               end

describe "site/editor gutter (headless)" do
  if (bin = CHROMIUM_BIN) && Process.find_executable("node")
    it "never soft-wraps a line and keeps the gutter's scrollTop synced to the textarea's" do
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run("node", ["spec/support/editor_gutter_check.mjs", bin], output: output, error: errors)
      status.success?.should be_true, "editor_gutter_check.mjs failed: #{output}\n#{errors}"
      report = JSON.parse(output.to_s)
      report["ok"].as_bool.should be_true
    end
  else
    pending "never soft-wraps a line and keeps the gutter's scrollTop synced to the textarea's (needs node and a browser: CHROMIUM_BIN, chromium, chromium-browser, google-chrome or google-chrome-stable)"
  end
end
