require "./spec_helper"
require "../src/browser"
require "json"

# Exercise the browser decoder against the native battle bridge's real
# binary frame log. Node imports the same module used by both battle pages.
describe "site/battle-playback frame coordinates" do
  if Process.find_executable("node")
    it "decodes moving robots and missiles into battlefield meters" do
      mover = "main(\"Mover\") do\n  drive(0, 45)\n  while true\n    if loc_x > 500\n      cannon(180, 100)\n    else\n      cannon(0, 100)\n    end\n    sleep\n  end\nend\n"
      opponent = "main(\"Opponent\") do\n  drive(180, 45)\n  while true\n    sleep\n  end\nend\n"
      request = {robots: [{name: "mover", source: mover}, {name: "opponent", source: opponent}], seed: 1_u64, limit: 3_000_i64, max_frames: 300}.to_json
      ptr = CrystalRobots::Browser.battle_alloc(request.bytesize)
      ptr.copy_from(request.to_unsafe, request.bytesize)
      CrystalRobots::Browser.battle_run
      report = JSON.parse(String.new(Bytes.new(CrystalRobots::Browser.battle_result_ptr, CrystalRobots::Browser.battle_result_len)))
      report["error"]?.should be_nil
      frames = Bytes.new(CrystalRobots::Browser.battle_frames_ptr, CrystalRobots::Browser.battle_frames_len)

      file = File.tempfile("crd-battle-playback", ".bin")
      begin
        file.write(frames)
        file.flush
        output = IO::Memory.new
        errors = IO::Memory.new
        status = Process.run("node", ["spec/support/battle_playback_check.mjs", file.path], output: output, error: errors)
        status.success?.should be_true, "battle_playback_check.mjs failed: #{output}\n#{errors}"
        JSON.parse(output.to_s)["ok"].as_bool.should be_true
      ensure
        file.delete
      end
    end
  else
    pending "decodes moving robots and missiles into battlefield meters (no node binary on this machine)"
  end
end
