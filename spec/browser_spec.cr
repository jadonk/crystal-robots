require "./spec_helper"
require "../src/browser"

# `src/browser.cr` compiles natively too (nothing in its Crystal source is
# wasm32-specific -- only the target it is *also* cross-compiled for is),
# so these specs call `CrystalRobots::Browser` directly, the same
# `alloc`/`run`-style entry points `crd_battle_alloc`/`crd_battle_run`
# wrap for wasm32, without needing the compiled `site/crystal-robots.wasm`
# or `node` (see `spec/wasm32_spec.cr` for the full cross-compilation
# fidelity checks, gated on `-Dcrd_wasm32`).
private def run_battle(request : String) : {JSON::Any, Bytes}
  ptr = CrystalRobots::Browser.battle_alloc(request.bytesize)
  ptr.copy_from(request.to_unsafe, request.bytesize)
  CrystalRobots::Browser.battle_run
  report = JSON.parse(String.new(Bytes.new(CrystalRobots::Browser.battle_result_ptr, CrystalRobots::Browser.battle_result_len)))
  frames = Bytes.new(CrystalRobots::Browser.battle_frames_ptr, CrystalRobots::Browser.battle_frames_len)
  {report, frames}
end

# Decodes the header `Browser.encode_frames` documents in `src/browser.cr`:
# `{version, robot_count, missile_slots, frame_count}`.
private def frame_header(frames : Bytes) : {UInt8, UInt8, UInt16, UInt32}
  io = IO::Memory.new(frames)
  {io.read_bytes(UInt8), io.read_bytes(UInt8), io.read_bytes(UInt16, IO::ByteFormat::LittleEndian), io.read_bytes(UInt32, IO::ByteFormat::LittleEndian)}
end

BROWSER_SPEC_IDLE    = "main(\"Idle\") do\n  while true\n    sleep\n  end\nend\n"
BROWSER_SPEC_SHOOTER = "main(\"S\") do\n  while true\n    cannon(0, 5)\n    sleep\n  end\nend\n"

private def idle_pair_request(limit : Int64, max_frames : Int32? = nil) : String
  h = {robots: [{name: "a", source: BROWSER_SPEC_IDLE}, {name: "b", source: BROWSER_SPEC_IDLE}], seed: 1_u64, limit: limit}
  (max_frames ? h.merge({max_frames: max_frames}) : h).to_json
end

private def shooter_pair_request(limit : Int64, max_frames : Int32) : String
  {robots: [{name: "s", source: BROWSER_SPEC_SHOOTER}, {name: "i", source: BROWSER_SPEC_IDLE}], seed: 1_u64, limit: limit, max_frames: max_frames}.to_json
end

describe "CrystalRobots::Browser.battle_run" do
  it "reports a frame_count matching the binary log's own header" do
    report, frames = run_battle(idle_pair_request(300_000_i64, 300))
    _version, robot_count, _slots, frame_count = frame_header(frames)
    frame_count.should eq report["frame_count"].as_i
    robot_count.should eq 2
  end

  it "records roughly the requested budget's worth of frames when nothing eventful happens" do
    small, _ = run_battle(idle_pair_request(300_000_i64, 300))
    large, _ = run_battle(idle_pair_request(300_000_i64, 6000))
    small["frame_count"].as_i.should be < 600
    large["frame_count"].as_i.should be > 3000
    large["frame_count"].as_i.should be > small["frame_count"].as_i * 5
  end

  it "clamps a non-positive max_frames instead of dividing by zero" do
    report, _ = run_battle(idle_pair_request(300_000_i64, 0))
    report["error"]?.should be_nil
    # clamped to Browser::BATTLE_FRAMES_MIN (200): far fewer frames than an
    # unclamped budget of 0 (a division by zero) could ever have produced.
    report["frame_count"].as_i.should be > 100
    report["frame_count"].as_i.should be < 400
  end

  # Phase 6: the browser gets a budget two orders of magnitude larger than
  # the served page or the CLI (`Browser::BATTLE_FRAMES_DEFAULT`), and a
  # cannon-fire event is still never dropped regardless of the budget --
  # the same guarantee `spec/battle_spec.cr` proves for `Field` directly,
  # here proven through the actual JSON request/binary response bridge
  # `crd_battle_run` uses.
  it "never drops a cannon-fire event's frame at a tight budget, through the JSON/binary bridge" do
    report, frames = run_battle(shooter_pair_request(30_000_i64, 2))
    report["error"]?.should be_nil
    _version, robot_count, slots, frame_count = frame_header(frames)
    io = IO::Memory.new(frames)
    io.skip(8)
    impacts = 0
    frame_count.times do
      io.skip(4)                        # cycle
      robot_count.times { io.skip(12) } # robot record: 10 bytes + damage + flags
      (robot_count.to_i32 * slots.to_i32).times do
        io.skip(4)
        flags = io.read_bytes(UInt8)
        impacts += 1 if flags & 2 != 0 # exploding
        io.read_bytes(UInt8)           # padding
      end
    end
    impacts.should be >= 10
    frame_count.should be > 2
  end

  it "defaults to a two-orders-of-magnitude larger budget than the served page keeps" do
    report, _ = run_battle(idle_pair_request(300_000_i64))
    report["frame_count"].as_i.should be > 1000
  end
end
