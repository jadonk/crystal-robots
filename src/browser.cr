require "./compiler"
require "./battle/step_robot"
require "./battle/svg_replay"
require "json"

# Browser entry points for the `wasm32-unknown-wasi` build (Phase 5b-1):
# a hand-written JS WASI shim (`site/wasi-shim.js`) calls these to run one
# pasted robot through the same passes `src/web/cgi.cr`'s parse page runs
# server-side -- tokenize/parse, check, interpret, emit WASM -- entirely
# client-side, no server round-trip.
#
# WASI's application ABI only defines `_start`, called once by the host;
# nothing stops the module from answering further calls afterward, because
# `_start` only calls `proc_exit` when the program's exit status is
# non-zero (see `/usr/lib/crystal/core/crystal/system/wasi/main.cr`).
# `_start` still runs first and does the one-time GC/runtime init every
# Crystal program needs (`Crystal.main`), so the shim must call it before
# anything below. The functions at the bottom are declared `fun` at the
# top level, which is how Crystal exports a function under its own name
# (rather than Crystal's mangled one) for WebAssembly or C to call.
#
# Crystal 1.18.2 stubs out exception handling for `wasm32`: `raise`
# (see `/usr/lib/crystal/core/raise.cr`) prints the exception to stderr
# and traps the module (a debugtrap, i.e. an `unreachable` instruction)
# instead of unwinding to any `rescue`, however close -- confirmed here by
# testing, not just reading the source: a `rescue` sitting directly around
# the `raise` in the same function still never runs. So a parse error, the
# interpreter's step limit or a `WASM_Emitter::Unsupported` source is
# unrecoverable *within a call*: the shim (`site/wasi-shim.js`) treats a
# trap as "this call failed," reads whatever it printed to stderr, and
# starts a fresh instance for the next call, exactly as it would for any
# other exported function here that never runs at all.
#
# `crd_run` (derivation, checker, WASM emit) and `crd_interpret` (the
# interpreter trace) are two separate exports rather than one for the
# same reason: a `while true` fight loop -- how every real robot's `main`
# block is written -- hits the interpreter's step limit and traps. Giving
# it its own call means that trap cannot also take down the derivation
# and checker report `crd_run` already produced.
module CrystalRobots::Browser
  extend self

  @@input = Bytes.empty
  @@result = Bytes.empty
  @@wasm = Bytes.empty
  @@interpret_result = Bytes.empty
  @@check_result = Bytes.empty
  @@battle_input = Bytes.empty
  @@battle_result = Bytes.empty
  @@battle_frames = Bytes.empty

  # Reserves `len` bytes for the next call's source; the shim writes the
  # UTF-8 source into the returned offset before calling `crd_run`.
  def alloc(len : Int32) : Pointer(UInt8)
    @@input = Bytes.new(len)
    @@input.to_unsafe
  end

  def result_ptr : Pointer(UInt8)
    @@result.to_unsafe
  end

  def result_len : Int32
    @@result.size
  end

  def wasm_ptr : Pointer(UInt8)
    @@wasm.to_unsafe
  end

  def wasm_len : Int32
    @@wasm.size
  end

  def interpret_result_ptr : Pointer(UInt8)
    @@interpret_result.to_unsafe
  end

  def interpret_result_len : Int32
    @@interpret_result.size
  end

  # Parses, checks and emits WASM for the source most recently written via
  # `alloc`, and stores a JSON report in `@@result` (read back with
  # `result_ptr`/`result_len`) and, when the program compiles clean, the
  # emitted module in `@@wasm`. Traps on a parse error or an unsupported
  # source (see the module comment) rather than reporting one gracefully.
  def run : Int32
    @@wasm = Bytes.empty
    program = CrystalRobots::Compiler::Program.new(String.new(@@input))
    CrystalRobots::Compiler::Parser.parse(program)

    problems = CrystalRobots::Compiler::Checker.check(program)
    json = String.build do |io|
      io << '{'
      io << "\"passes\":" << program.passes << ','
      io << "\"derivation\":" << program.derivation.to_json << ','
      io << "\"problems\":[" << problems.map { |p| p.to_s.to_json }.join(",") << ']'
      if problems.empty?
        @@wasm = CrystalRobots::Compiler::WASM_Emitter.new(program).to_wasm
        io << ",\"wasm_len\":" << @@wasm.size
      end
      io << '}'
    end
    @@result = json.to_slice
    @@result.size
  end

  # Interprets the source most recently written via `alloc` (a fresh parse
  # of it, independent of `run`) and stores a JSON report in
  # `@@interpret_result`. Traps on a parse error, a runtime error or the
  # step limit (see the module comment), which the shim treats as "no
  # interpreter trace available" rather than losing `run`'s report too.
  def interpret : Int32
    program = CrystalRobots::Compiler::Program.new(String.new(@@input))
    CrystalRobots::Compiler::Parser.parse(program)

    interpreter = CrystalRobots::Compiler::Interpreter.new(program, CrystalRobots::Compiler::NullHost.new, 200_000)
    CrystalRobots::Compiler::Interpreter.puts_clear
    interpreter.run
    json = {status: "finished after #{interpreter.steps} steps", puts: CrystalRobots::Compiler::Interpreter.puts_out}.to_json
    @@interpret_result = json.to_slice
    @@interpret_result.size
  end

  def check_result_ptr : Pointer(UInt8)
    @@check_result.to_unsafe
  end

  def check_result_len : Int32
    @@check_result.size
  end

  # Parses (never raising -- `Parser.try_parse`/`try_lex`, the same
  # non-raising path `src/battle/step_robot.cr` uses to isolate a bad
  # robot's parse failure) and, on success, checks the source most
  # recently written via `alloc`, for the editor's live-typing loop (Phase
  # 6): unlike `run`, this never traps on a bad-but-still-typing source, so
  # the shim can call it after every debounced keystroke without
  # reinstantiating on every mistake. Stores a JSON report in
  # `@@check_result` (`{"passes":N,"derivation":"...","error":{"message",
  # "line","col"}|null,"problems":[{"message","line","col"}, ...]}`) --
  # `error` and a non-empty `problems` are mutually exclusive, since a
  # program with a parse error was never checked. The wording matches
  # `Compiler::Parser::Error#message` and `Checker::Problem#message`, the
  # same plain words `src/web/cgi.cr`'s served `/parse` page shows.
  def check : Int32
    program = CrystalRobots::Compiler::Program.new(String.new(@@input))
    err = CrystalRobots::Compiler::Parser.try_parse(program)
    json = String.build do |io|
      io << '{'
      io << "\"passes\":" << program.passes << ','
      io << "\"derivation\":" << program.derivation.to_json << ','
      if err
        io << "\"error\":{\"message\":" << err.message.to_s.to_json << ",\"line\":" << err.line << ",\"col\":" << err.col << "},"
        io << "\"problems\":[]"
      else
        problems = CrystalRobots::Compiler::Checker.check(program)
        io << "\"error\":null,"
        io << "\"problems\":[" << problems.map { |p| {message: p.message, line: p.line, col: p.col}.to_json }.join(",") << ']'
      end
      io << '}'
    end
    @@check_result = json.to_slice
    @@check_result.size
  end

  # Reserves `len` bytes for the next call's battle request: a JSON object
  # `{"robots":[{"name":..,"source":..}, 2 to 4 of these], "seed":N,
  # "limit":N, "max_frames":N}`, written by the shim before calling
  # `crd_battle_run`. `max_frames` is optional (defaults to
  # `BATTLE_FRAMES_DEFAULT` below); a `cps` key is accepted for backward
  # compatibility with older requests but ignored -- replay speed is a
  # client-side playback control now (`site/battle-playback.js`), not
  # something baked into a server-rendered SMIL duration.
  def battle_alloc(len : Int32) : Pointer(UInt8)
    @@battle_input = Bytes.new(len)
    @@battle_input.to_unsafe
  end

  def battle_result_ptr : Pointer(UInt8)
    @@battle_result.to_unsafe
  end

  def battle_result_len : Int32
    @@battle_result.size
  end

  # Bounds a page-supplied cycle limit the same way `src/web/cgi.cr`'s
  # served `/battle` page bounds its own `limit=` parameter: from one
  # motion cycle up to CROBOTS's own default limit.
  BATTLE_LIMIT_MIN = CrystalRobots::Battle::MOTION_CYCLES.to_i64
  BATTLE_LIMIT_MAX = CrystalRobots::Battle::CYCLE_LIMIT

  # Bounds a page-supplied frame budget (`max_frames` on the request,
  # `Field#initialize`'s own parameter). The served `/battle` page and the
  # native CLI keep a modest budget (400 and 200 respectively, `ANIM_FRAMES`
  # in `src/web/cgi.cr` and `Field`'s own default) because they still build
  # one SMIL keyframe list per recorded frame; the browser has no such
  # limit -- `site/battle-playback.js` reads the frame log as a typed
  # array and only ever touches the two frames bracketing "now" -- so its
  # default here is two orders of magnitude larger. Either way a battle
  # event (cannon fire, missile impact, damage, death, scan hit) always
  # gets its own frame in addition to the budget, per `Field#run_stepwise`
  # (`src/battle/step_robot.cr`) and `Field`'s `@event_pending` machinery
  # (`src/battle/field.cr`).
  BATTLE_FRAMES_MIN     =    200
  BATTLE_FRAMES_DEFAULT = 20_000
  BATTLE_FRAMES_MAX     = 60_000

  def battle_frames_ptr : Pointer(UInt8)
    @@battle_frames.to_unsafe
  end

  def battle_frames_len : Int32
    @@battle_frames.size
  end

  # Packs `field.frames` into the compact binary layout documented on
  # `encode_frames` below, for `crd_battle_frames_ptr`/`_len`. Every
  # numeric conversion here is the unchecked (`!`) form: an overflow
  # exception on this target traps the whole module instead of unwinding
  # (see the module comment on `crd_run`/`crd_interpret`), and none of
  # these values can realistically leave their declared ranges (clicks are
  # a small multiple of a 1000x1000 m field, angles are 0..359, damage is
  # 0..100) -- unchecked truncation is strictly safer here than a raise
  # that cannot be caught.
  #
  # Layout (little-endian throughout, read directly with a JS `DataView`):
  #
  #   offset 0: u8  version (1)
  #   offset 1: u8  robot_count (2..4)
  #   offset 2: u16 missile_slots (per robot; `Battle::MIS_ROBOT`, today 2)
  #   offset 4: u32 frame_count
  #   offset 8: `frame_count` frames, back to back, each:
  #     u32 cycle
  #     `robot_count` robot records, 12 bytes each, in robot order:
  #       i16 x, i16 y (clicks), i16 heading, i16 scan, i16 cannon (degrees,
  #       0..359), u8 damage (0..100), u8 flags (bit 0 active, bit 1 fired)
  #     `robot_count * missile_slots` missile records, 6 bytes each, in
  #     owner-major/slot-minor order (owner 0 slot 0, owner 0 slot 1,
  #     owner 1 slot 0, ...):
  #       i16 x, i16 y (clicks), u8 flags (bit 0 present, bit 1 exploding),
  #       u8 padding (0)
  #
  # Every robot and every missile slot occupies its record at every frame,
  # whether or not it did anything that frame (an unfired slot is present
  # with flags 0) -- a fixed stride per frame lets the reader index frame
  # `i` directly (`8 + i * frame_stride`) instead of parsing a
  # variable-length record, the reason for a typed-array transfer over one
  # JSON object per frame in the first place (a 500,000-cycle match can
  # log tens of thousands of frames; JSON.parse-ing that many small
  # objects is exactly the cost this format avoids).
  def self.encode_frames(field : CrystalRobots::Battle::Field) : Bytes
    n = field.robots.size
    slots = CrystalRobots::Battle::MIS_ROBOT
    frames = field.frames
    io = IO::Memory.new
    io.write_bytes(1_u8)
    io.write_bytes(n.to_u8!)
    io.write_bytes(slots.to_u16!, IO::ByteFormat::LittleEndian)
    io.write_bytes(frames.size.to_u32!, IO::ByteFormat::LittleEndian)
    frames.each do |f|
      io.write_bytes(f.cycle.to_u32!, IO::ByteFormat::LittleEndian)
      f.robots.each do |r|
        io.write_bytes(r.x.to_i16!, IO::ByteFormat::LittleEndian)
        io.write_bytes(r.y.to_i16!, IO::ByteFormat::LittleEndian)
        io.write_bytes(r.heading.to_i16!, IO::ByteFormat::LittleEndian)
        io.write_bytes(r.scan.to_i16!, IO::ByteFormat::LittleEndian)
        io.write_bytes(r.cannon.to_i16!, IO::ByteFormat::LittleEndian)
        io.write_bytes(r.damage.to_u8!)
        flags = 0_u8
        flags |= 1_u8 if r.active
        flags |= 2_u8 if r.fired
        io.write_bytes(flags)
      end
      n.times do |owner|
        slots.times do |slot|
          m = f.missiles.find { |st| st.owner == owner && st.slot == slot }
          if m
            io.write_bytes(m.x.to_i16!, IO::ByteFormat::LittleEndian)
            io.write_bytes(m.y.to_i16!, IO::ByteFormat::LittleEndian)
            mflags = 1_u8
            mflags |= 2_u8 if m.exploding
            io.write_bytes(mflags)
          else
            io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)
            io.write_bytes(0_i16, IO::ByteFormat::LittleEndian)
            io.write_bytes(0_u8)
          end
          io.write_bytes(0_u8) # padding, keeps the missile record even-sized
        end
      end
    end
    io.to_slice
  end

  # Runs one match -- `CrystalRobots::Battle::Field#run_stepwise` (see
  # `src/battle/step_robot.cr`): the same battlefield physics and the same
  # tree-walking interpreter `bin/crystal-robots`'s own matches use, driven
  # without fibers or `raise`, both unsafe on this target (see the module
  # comment on `crd_run`/`crd_interpret`, and `step_robot.cr`'s own header)
  # -- for the source most recently written via `battle_alloc`, and stores
  # a JSON report (final standings plus a static SVG "skeleton",
  # `CrystalRobots::Battle.svg_skeleton`, `src/battle/svg_replay.cr`) in
  # `@@battle_result`, and the per-cycle frame log itself, packed by
  # `encode_frames` above, in `@@battle_frames` (`crd_battle_frames_ptr`/
  # `_len`). Phase 6 correction: this used to render the whole match as one
  # SMIL-animated SVG string (`Battle.svg_animation`) the way the served
  # `/battle` page still does; with a frame budget now two orders of
  # magnitude larger for the in-page battle (`max_frames` below), building
  # that many `<animate>` keyframes would be exactly the slow, unresponsive
  # rendering this phase exists to fix, so the frame log goes to
  # `site/battle-playback.js` instead, which draws only the two frames
  # bracketing "now" per `requestAnimationFrame` tick. A robot whose source
  # fails to parse or check is reported inactive with its `error`, same as
  # the served `/battle` page; it does not stop the match or this call.
  # Traps only on a malformed request (the page's own bug, not a robot's)
  # -- see the module comment.
  def battle_run : Int32
    payload = JSON.parse(String.new(@@battle_input))
    robots = payload["robots"].as_a
    seed = (payload["seed"]?.try(&.as_i64?) || 1_i64).to_u64
    limit = (payload["limit"]?.try(&.as_i64?) || BATTLE_LIMIT_MAX).clamp(BATTLE_LIMIT_MIN, BATTLE_LIMIT_MAX)
    max_frames = (payload["max_frames"]?.try(&.as_i?) || BATTLE_FRAMES_DEFAULT).clamp(BATTLE_FRAMES_MIN, BATTLE_FRAMES_MAX)

    json = String.build do |io|
      if robots.size < 2 || robots.size > 4
        @@battle_frames = Bytes.empty
        io << {error: "a battle needs 2 to 4 robots, got #{robots.size}"}.to_json
      else
        entries = robots.map { |r| {r["name"].as_s, r["source"].as_s} }
        field = CrystalRobots::Battle::Field.new(entries, seed: seed, limit: limit, max_frames: max_frames).run_stepwise
        @@battle_frames = Browser.encode_frames(field)
        io << '{'
        io << "\"seed\":" << seed << ','
        io << "\"limit\":" << limit << ','
        io << "\"cycles\":" << field.cycles << ','
        io << "\"frame_count\":" << field.frames.size << ','
        io << "\"robot_count\":" << field.robots.size << ','
        io << "\"missile_slots\":" << CrystalRobots::Battle::MIS_ROBOT << ','
        io << "\"winner\":" << field.winner.try(&.name).to_json << ','
        io << "\"robots\":[" << field.robots.map { |r|
          {name: r.name, active: r.active, damage: r.damage, error: r.error, restarts: r.restarts, cycles: r.cycles}.to_json
        }.join(",") << "],"
        io << "\"skeleton\":" << CrystalRobots::Battle.svg_skeleton(field).to_json
        io << '}'
      end
    end
    @@battle_result = json.to_slice
    @@battle_result.size
  end
end

# Allocates `len` bytes and returns their address; the shim writes the
# pasted robot's UTF-8 source there before calling `crd_run`.
fun crd_alloc(len : Int32) : UInt8*
  CrystalRobots::Browser.alloc(len)
end

# Parses, checks and emits WASM for the source last written via
# `crd_alloc`; returns the JSON report's length, read with
# `crd_result_ptr`/`crd_result_len`.
fun crd_run : Int32
  CrystalRobots::Browser.run
end

fun crd_result_ptr : UInt8*
  CrystalRobots::Browser.result_ptr
end

fun crd_result_len : Int32
  CrystalRobots::Browser.result_len
end

# The WASM module emitted by the last `crd_run`, when it compiled clean.
fun crd_wasm_ptr : UInt8*
  CrystalRobots::Browser.wasm_ptr
end

fun crd_wasm_len : Int32
  CrystalRobots::Browser.wasm_len
end

# Interprets the source last written via `crd_alloc`, independently of
# `crd_run`; may trap (see the module comment above). Returns the JSON
# report's length, read with `crd_interpret_result_ptr`/`_len`.
fun crd_interpret : Int32
  CrystalRobots::Browser.interpret
end

fun crd_interpret_result_ptr : UInt8*
  CrystalRobots::Browser.interpret_result_ptr
end

fun crd_interpret_result_len : Int32
  CrystalRobots::Browser.interpret_result_len
end

# Parses and checks the source last written via `crd_alloc`, for the
# editor's live-typing loop (Phase 6); never traps on a bad-but-typing
# source, unlike `crd_run` (see `Browser.check`'s module comment). Returns
# the JSON report's length, read with `crd_check_result_ptr`/`_len`.
fun crd_check : Int32
  CrystalRobots::Browser.check
end

fun crd_check_result_ptr : UInt8*
  CrystalRobots::Browser.check_result_ptr
end

fun crd_check_result_len : Int32
  CrystalRobots::Browser.check_result_len
end

# Allocates `len` bytes and returns their address; the shim writes the
# battle request JSON there before calling `crd_battle_run`.
fun crd_battle_alloc(len : Int32) : UInt8*
  CrystalRobots::Browser.battle_alloc(len)
end

# Runs the match described by the request last written via
# `crd_battle_alloc`; returns the JSON report's length, read with
# `crd_battle_result_ptr`/`crd_battle_result_len`. May trap on a
# malformed request (see the module comment above `Browser.battle_run`).
fun crd_battle_run : Int32
  CrystalRobots::Browser.battle_run
end

fun crd_battle_result_ptr : UInt8*
  CrystalRobots::Browser.battle_result_ptr
end

fun crd_battle_result_len : Int32
  CrystalRobots::Browser.battle_result_len
end

# The match's per-cycle frame log, packed by `Browser.encode_frames`
# (layout documented there) for the last `crd_battle_run`; read with
# `crd_battle_frames_ptr`/`crd_battle_frames_len`.
fun crd_battle_frames_ptr : UInt8*
  CrystalRobots::Browser.battle_frames_ptr
end

fun crd_battle_frames_len : Int32
  CrystalRobots::Browser.battle_frames_len
end
