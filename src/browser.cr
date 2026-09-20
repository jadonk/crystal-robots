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
  @@battle_input = Bytes.empty
  @@battle_result = Bytes.empty

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

  # Reserves `len` bytes for the next call's battle request: a JSON object
  # `{"robots":[{"name":..,"source":..}, 2 to 4 of these], "seed":N,
  # "limit":N, "cps":N}`, written by the shim before calling
  # `crd_battle_run`.
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

  # Runs one match -- `CrystalRobots::Battle::Field#run_stepwise` (see
  # `src/battle/step_robot.cr`): the same battlefield physics and the same
  # tree-walking interpreter `bin/crystal-robots`'s own matches use, driven
  # without fibers or `raise`, both unsafe on this target (see the module
  # comment on `crd_run`/`crd_interpret`, and `step_robot.cr`'s own header)
  # -- for the source most recently written via `battle_alloc`, and stores
  # a JSON report (final standings plus the SVG SMIL replay
  # `CrystalRobots::Battle.svg_animation` renders from the finished
  # `Field`, `src/battle/svg_replay.cr`, the same renderer the served
  # `/battle` page uses) in `@@battle_result`. The per-cycle frame log
  # itself stays inside this call, not part of the report: the page has no
  # use for it once the SVG is built. A robot whose source fails to parse
  # or check is reported inactive with its `error`, same as the served
  # `/battle` page; it does not stop the match or this call. Traps only on
  # a malformed request (the page's own bug, not a robot's) -- see the
  # module comment.
  def battle_run : Int32
    payload = JSON.parse(String.new(@@battle_input))
    robots = payload["robots"].as_a
    seed = (payload["seed"]?.try(&.as_i64?) || 1_i64).to_u64
    limit = (payload["limit"]?.try(&.as_i64?) || BATTLE_LIMIT_MAX).clamp(BATTLE_LIMIT_MIN, BATTLE_LIMIT_MAX)
    cps = (payload["cps"]?.try(&.as_i?) || CrystalRobots::Battle::ANIM_CPS).clamp(1, 20_000)

    json = String.build do |io|
      if robots.size < 2 || robots.size > 4
        io << {error: "a battle needs 2 to 4 robots, got #{robots.size}"}.to_json
      else
        entries = robots.map { |r| {r["name"].as_s, r["source"].as_s} }
        field = CrystalRobots::Battle::Field.new(entries, seed: seed, limit: limit).run_stepwise
        io << '{'
        io << "\"seed\":" << seed << ','
        io << "\"limit\":" << limit << ','
        io << "\"cycles\":" << field.cycles << ','
        io << "\"winner\":" << field.winner.try(&.name).to_json << ','
        io << "\"robots\":[" << field.robots.map { |r|
          {name: r.name, active: r.active, damage: r.damage, error: r.error, restarts: r.restarts, cycles: r.cycles}.to_json
        }.join(",") << "],"
        io << "\"svg\":" << CrystalRobots::Battle.svg_animation(field, cps).to_json
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
