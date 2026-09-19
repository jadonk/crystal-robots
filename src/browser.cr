require "./compiler/program"
require "./compiler/parser"
require "./compiler/checker"
require "./compiler/interpreter"
require "./compiler/wasm_emitter"
require "json"

# Browser entry points for the `wasm32-unknown-wasi` build: a
# hand-written JS WASI shim (`site/wasi-shim.js`) calls these to run
# one pasted robot through the same passes `src/web/app.cr`'s parse
# page runs server-side -- tokenize/parse, check, interpret, emit
# WASM -- entirely client-side, no server round-trip.
#
# WASI's application ABI only defines `_start`, called once by the
# host; nothing stops the module from answering further calls
# afterward, because `_start` only calls `proc_exit` when the
# program's exit status is non-zero (see
# `/usr/lib/crystal/core/crystal/system/wasi/main.cr`). `_start`
# still runs first and does the one-time GC/runtime init every
# Crystal program needs (`Crystal.main`), so the shim must call it
# before anything below. The functions at the bottom are declared
# `fun` at the top level, which is how Crystal exports a function
# under its own name (rather than Crystal's mangled one) for
# WebAssembly or C to call.
#
# Crystal 1.18.2 stubs out exception handling for `wasm32`: `raise`
# (see `/usr/lib/crystal/core/raise.cr`) prints the exception to
# stderr and traps the module (a debugtrap, i.e. an `unreachable`
# instruction) instead of unwinding to any `rescue`, however close --
# confirmed here by testing, not just reading the source: a `rescue`
# sitting directly around the `raise` in the same function still
# never runs. So a parse error, the interpreter's own cycle limit
# (see `Interpreter#limit`, added for exactly this call) or a
# `WASM_Emitter::Unsupported` source is unrecoverable *within a
# call*: the shim (`site/wasi-shim.js`) treats a trap as "this call
# failed," reads whatever it printed to stderr, and starts a fresh
# instance for the next call, exactly as it would for any other
# exported function here that never runs at all.
#
# `crd_run` (derivation, checker, WASM emit) and `crd_interpret` (the
# interpreter trace) are two separate exports rather than one for the
# same reason: a `while true` fight loop -- how every real robot's
# `main` block is written -- hits the interpreter's cycle limit and
# traps. Giving it its own call means that trap cannot also take down
# the derivation and checker report `crd_run` already produced.
module CrystalRobots::Browser
  extend self

  @@input = Bytes.empty
  @@result = Bytes.empty
  @@wasm = Bytes.empty
  @@interpret_result = Bytes.empty

  # Reserves `len` bytes for the next call's source; the shim writes
  # the UTF-8 source into the returned offset before calling `crd_run`.
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

  # A standalone interpreter run, with no battlefield to bound a
  # `while true` main block, gets a plain cycle cap instead -- generous
  # enough to let a real robot's setup and a few sweeps run, small
  # enough that a browser tab notices quickly if a paste never returns.
  INTERPRET_LIMIT = 200_000_i64

  # Parses, checks and emits WASM for the source most recently written
  # via `alloc`, and stores a JSON report in `@@result` (read back with
  # `result_ptr`/`result_len`) and, when the program compiles clean,
  # the emitted module in `@@wasm`. Traps on a parse error or an
  # unsupported source (see the module comment) rather than reporting
  # one gracefully.
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

  # Interprets the source most recently written via `alloc` (a fresh
  # parse of it, independent of `run`) and stores a JSON report in
  # `@@interpret_result`. Traps on a parse error or a runtime error
  # (see the module comment), which the shim treats as "no interpreter
  # trace available" rather than losing `run`'s report too.
  def interpret : Int32
    program = CrystalRobots::Compiler::Program.new(String.new(@@input))
    CrystalRobots::Compiler::Parser.parse(program)

    host = CrystalRobots::Compiler::NullHost.new
    interpreter = CrystalRobots::Compiler::Interpreter.new(program, host, limit: INTERPRET_LIMIT)
    interpreter.run
    json = {status: "finished after #{interpreter.cycles} cycles", puts: host.puts_out}.to_json
    @@interpret_result = json.to_slice
    @@interpret_result.size
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
