require "./field"

# A second execution path for `Robot`, alongside the fiber-based
# `start`/`cycle`/`stop` in `field.cr`: `start_stepwise`/`step!` run the
# same program, against the same `RobotHost`, at the same per-cycle
# granularity, but without `spawn`/`Channel`/`Fiber` and without ever
# calling `raise` once a match is under way.
#
# Both restrictions come from `wasm32-unknown-wasi`, which is the reason
# this file exists (see `src/browser.cr`'s `crd_battle`): Crystal 1.18.2
# has no working exception handling on that target at all -- `raise`
# always traps the module, even a `raise` immediately rescued in the same
# function (confirmed for `crd_run`/`crd_interpret`, Phase 5b-1) -- so a
# robot's runtime error or step budget cannot be signalled by raising and
# rescuing the way `field.cr`'s `Interpreter::RuntimeError`/`StepLimit`
# are. And a battle needs several robots' programs interleaved one
# instruction at a time, which `field.cr` gets from a fiber per robot
# parked on a `Channel` inside `Interpreter#on_step`; whether `spawn`
# reliably schedules fibers at all on this target, once `_start` has
# already returned control to the WASI host and Crystal's own event loop
# is no longer the thing driving execution, is not something this project
# trusts (a plain `Fiber.new`/`resume`/`Fiber.yield` loop already turned
# out not to behave as expected on the *native* runtime during an earlier,
# unrelated rewrite -- see docs/PLAN.md -- so a second, less-exercised
# concurrency primitive is not a chance worth taking on a target with no
# safety net for getting it wrong).
#
# The technique: every place the tree-walking `Interpreter` (see
# `interpreter.cr`) would recurse -- evaluate this subexpression, then do
# X with the result -- is written here in continuation-passing style: a
# `Proc` to call with the result, instead of a plain return. `tick`, the
# one place that charges a CROBOTS cycle, is the only place that ever
# *doesn't* call its continuation immediately: it stores the continuation
# in `@resume` and returns, unwinding the real (native) call stack all
# the way back out to `step!` -- no exception, no fiber, just an ordinary
# method return. The next `step!` call resumes by invoking `@resume`,
# which re-enters exactly where it left off (the closures captured
# whatever state they needed), runs synchronously through however much
# bookkeeping is free, and pauses again at the next `tick`. One `step!`
# call therefore does exactly one charged cycle-unit of work, the same
# granularity `field.cr`'s fiber hands the scheduler.
#
# A runtime error (undefined call, non-numeric operand, call depth) calls
# `runtime_error` instead of raising; a `break`/`return` calls the
# innermost loop's exit or the innermost call's return continuation
# instead of raising `BreakSignal`/`ReturnSignal`. Both just stop calling
# further continuations -- in CPS, not calling the continuation *is*
# unwinding, no stack to unwind explicitly.
#
# Globals, constants and `def`s are processed once (not once per restart,
# unlike `field.cr`'s fiber path, which rebuilds a fresh `Interpreter` --
# and so a fresh `@globals` -- on every restart): `global` naming this
# "global" only makes sense if it survives `main` restarting, and no
# example or wiki robot's top-level code depends on being re-run.
module CrystalRobots::Battle
  alias Value = CrystalRobots::Compiler::Value
  alias Type = CrystalRobots::Compiler::Type

  # One suspended user-function (or `main`) activation: where to send the
  # return value, and how far `@break_stack` must be truncated if a
  # `return` fires from inside one or more loops in this activation (a
  # loop's own exit is popped as it exits normally or via `break`, but an
  # explicit `return` abandons any loops still open in the current call).
  private record CallCtx, return_cont : Proc(Value, Nil), break_depth : Int32

  private record StepFunction, params : Array(String), body : Array(Int32)

  class Robot
    @resume : Proc(Nil)? = nil
    @host : RobotHost? = nil
    @initialized = false
    @main_body : Array(Int32)? = nil
    @globals = {} of String => Value
    @constants = {} of String => Value
    @functions = {} of String => StepFunction
    @frames = [] of Hash(String, Value)
    @break_stack = [] of Proc(Value?, Nil)
    @return_stack = [] of CallCtx
    @halted = false
    @attempt_done : Symbol? = nil
    @attempt_error : String? = nil
    property step_costs : Compiler::Interpreter::Costs = Compiler::Interpreter::Costs.crobots

    # Parse and check the program, same gate as `start`; does not spawn
    # anything, and -- unlike `start`, which lets `Parser.new` raise and
    # relies on a native `rescue` -- never raises: `Parser.try_parse`
    # reports a bad source as a return value, since a `raise` here would
    # trap the whole match on `wasm32-unknown-wasi` (see the module
    # comment), not just fail this one robot. `step!` is a no-op until
    # this succeeds.
    def start_stepwise : Nil
      program = Compiler::Program.new(@source)
      if (parse_error = Compiler::Parser.try_parse(program))
        @error = parse_error.message
        @active = false
        return
      end
      @program = program
      problems = Compiler::Checker.check(@program.not_nil!)
      unless problems.empty?
        @error = problems.map(&.to_s).join("; ")
        @active = false
        return
      end
      @active = true
      @host = RobotHost.new(self, @field)
    end

    # Advance this robot by exactly one charged cycle-unit: resume the
    # suspended computation, or start the next attempt at running `main`.
    # When that unit was the last of an attempt -- `main` returned or fell
    # through, or a runtime error fired -- restarts (CROBOTS restarts
    # `main` on return or failure) unless repeated errors mark the robot
    # failed, mirroring `field.cr`'s fiber path.
    def step! : Nil
      return unless @active
      @attempt_done = nil
      @halted = false
      if (r = @resume)
        @resume = nil
        r.call
      else
        start_attempt
      end
      case @attempt_done
      when :error
        message = @attempt_error || "runtime error"
        note("runtime error: #{message}")
        if (@errors += 1) >= MAX_ERRORS
          @error = message
          @active = false
        else
          @restarts += 1
          @cycles += 1
          @resume = -> { start_attempt }
        end
      when :completed
        @restarts += 1
        @cycles += 1
        @resume = -> { start_attempt }
      else
        # paused mid-attempt; nothing else to do this round
      end
    end

    private def start_attempt : Nil
      program = @program
      return if program.nil?
      if @initialized
        run_main(program)
      else
        @initialized = true
        init_top_level(program) { run_main(program) }
      end
    end

    private def attempt_completed : Nil
      @halted = true
      @attempt_done = :completed
    end

    private def runtime_error(message : String) : Nil
      return if @halted
      @halted = true
      @attempt_done = :error
      @attempt_error = message
    end

    # ---- top-level: defs registered once, globals/consts evaluated once ----

    private def init_top_level(program : Compiler::Program, &done : -> Nil) : Nil
      root_kids = program.children(program.root)
      root_kids.each { |stmt| define_function(program, stmt) if program[stmt].rule == :def }
      main_stmt = root_kids.find { |stmt| program[stmt].rule == :main }
      @main_body = main_stmt ? body_of(program, main_stmt) : [] of Int32
      others = root_kids.reject { |stmt| program[stmt].rule.in?(:def, :main) }
      init_top_seq(program, others, 0, done)
    end

    private def define_function(program : Compiler::Program, stmt : Int32) : Nil
      head = program.arg(stmt, 0)
      names = program.children(head).select { |i| program.type(i) == Type::Identifier }.map { |i| program.lexeme(i) }
      return if names.empty?
      @functions[names[0]] = StepFunction.new(names[1..], body_of(program, stmt))
    end

    private def body_of(program : Compiler::Program, block : Int32) : Array(Int32)
      program.children(block).select { |i| program.type(i) == Type::Statement }
    end

    private def init_top_seq(program : Compiler::Program, stmts : Array(Int32), index : Int32, done : -> Nil) : Nil
      return if @halted
      if index >= stmts.size
        done.call
        return
      end
      stmt = stmts[index]
      if program[stmt].rule == :global
        declare_global(program, stmt) do |_|
          next if @halted
          init_top_seq(program, stmts, index + 1, done)
        end
      else
        exec_top(program, stmt) do
          next if @halted
          init_top_seq(program, stmts, index + 1, done)
        end
      end
    end

    # A bare top-level statement: a constant assignment is stored directly
    # (so later constants and `main` can see it); anything else runs with
    # the constants collected so far as its one local frame.
    private def exec_top(program : Compiler::Program, stmt : Int32, &done : -> Nil) : Nil
      return if @halted
      expr = program.arg(stmt, 0)
      if program[stmt].rule == :exprstmt && program[expr].rule == :assign
        name = program.lexeme(program.arg(expr, 0))
        eval(program, program.arg(expr, 2)) do |value|
          next if @halted
          tick(@step_costs.store) do
            next if @halted
            @constants[name] = value
            tick(@step_costs.statement) { done.call }
          end
        end
      else
        @frames << @constants
        exec(program, stmt) do |_value|
          next if @halted
          @frames.pop?
          done.call
        end
      end
    end

    private def declare_global(program : Compiler::Program, stmt : Int32, &cont : Value? -> Nil) : Nil
      return if @halted
      kids = program.children(stmt)
      eval(program, kids[4]) do |value|
        next if @halted
        @globals[program.lexeme(kids[2])] = value
        cont.call(value)
      end
    end

    # ---- running (and restarting) `main` ----

    private def run_main(program : Compiler::Program) : Nil
      @frames = [{} of String => Value]
      @return_stack = [] of CallCtx
      @break_stack = [] of Proc(Value?, Nil)
      push_call(->(_v : Value) { attempt_completed })
      body = @main_body || [] of Int32
      exec_body(program, body, 0, 0.as(Value), ->(last : Value) { finish_call(last) })
    end

    private def push_call(return_cont : Proc(Value, Nil)) : Nil
      @return_stack << CallCtx.new(return_cont, @break_stack.size)
    end

    # Explicit `return`, or a function/`main` body falling off the end:
    # both hand a value to the innermost pending call, truncating any
    # loops still open inside it (a `return` from inside a `while` never
    # runs that loop's own exit continuation).
    private def finish_call(value : Value) : Nil
      return if @halted
      ctx = @return_stack.pop?
      if ctx.nil?
        runtime_error("return outside of a call")
        return
      end
      @break_stack = @break_stack[0, ctx.break_depth] if @break_stack.size > ctx.break_depth
      @frames.pop?
      ctx.return_cont.call(value)
    end

    private def do_break : Nil
      return if @halted
      top = @break_stack.last?
      if top
        top.call(nil)
      else
        runtime_error("break outside of a loop")
      end
    end

    private def call_user(program : Compiler::Program, name : String, args : Array(Value), cont : Value -> Nil) : Nil
      return if @halted
      fn = @functions[name]?
      if fn.nil?
        runtime_error("undefined function #{name}")
        return
      end
      if @frames.size > Compiler::Interpreter::MAX_CALL_DEPTH
        runtime_error("call depth exceeded #{Compiler::Interpreter::MAX_CALL_DEPTH} in #{name}")
        return
      end
      if fn.params.size != args.size
        runtime_error("#{name} expects #{fn.params.size} arguments, got #{args.size}")
        return
      end
      frame = {} of String => Value
      fn.params.each_with_index { |param, k| frame[param] = args[k] }
      @frames << frame
      push_call(cont)
      exec_body(program, fn.body, 0, 0.as(Value), ->(last : Value) { finish_call(last) })
    end

    # ---- statement sequencing ----

    private def exec_body(program : Compiler::Program, stmts : Array(Int32), index : Int32, last : Value, done : Value -> Nil) : Nil
      return if @halted
      if index >= stmts.size
        done.call(last)
        return
      end
      exec(program, stmts[index]) do |value|
        next if @halted
        exec_body(program, stmts, index + 1, value || 0, done)
      end
    end

    private def exec(program : Compiler::Program, stmt : Int32, &cont : Value? -> Nil) : Nil
      return if @halted
      n = program[stmt]
      case n.rule
      when :exprstmt
        eval(program, program.arg(stmt, 0)) do |value|
          next if @halted
          tick(@step_costs.statement) { cont.call(value) }
        end
      when :return
        kids = program.children(stmt)
        if kids.size > 2
          eval(program, kids[1]) do |value|
            next if @halted
            tick(@step_costs.branch) { finish_call(value) }
          end
        else
          tick(@step_costs.branch) { finish_call(0) }
        end
      when :break
        tick(@step_costs.branch) { do_break }
      when :if
        exec_if(program, stmt, cont)
      when :while
        exec_loop(program, stmt, true, cont)
      when :until
        exec_loop(program, stmt, false, cont)
      when :case
        exec_case(program, stmt, cont)
      when :global
        declare_global(program, stmt) { |_v| cont.call(nil) }
      when :def
        cont.call(nil)
      else
        runtime_error("cannot execute #{n.rule}")
      end
    end

    private def exec_if(program : Compiler::Program, stmt : Int32, cont : Value? -> Nil) : Nil
      return if @halted
      exec_if_seq(program, program.children(stmt), 0, false, nil, cont)
    end

    private def exec_if_seq(program : Compiler::Program, kids : Array(Int32), index : Int32, taken : Bool, result : Value?, cont : Value? -> Nil) : Nil
      return if @halted
      if index >= kids.size
        cont.call(result)
        return
      end
      k = kids[index]
      case program.type(k)
      when Type::IfHead, Type::ElsifHead
        if taken
          cont.call(result)
          return
        end
        eval(program, program.arg(k, 1)) do |v|
          next if @halted
          is_taken = truthy?(v)
          tick(@step_costs.branch) do
            next if @halted
            exec_if_seq(program, kids, index + 1, is_taken, result, cont)
          end
        end
      when Type::ElseKeyword
        if taken
          cont.call(result)
        else
          exec_if_seq(program, kids, index + 1, true, result, cont)
        end
      when Type::Statement
        if taken
          exec(program, k) do |v|
            next if @halted
            exec_if_seq(program, kids, index + 1, taken, v, cont)
          end
        else
          exec_if_seq(program, kids, index + 1, taken, result, cont)
        end
      else
        exec_if_seq(program, kids, index + 1, taken, result, cont)
      end
    end

    private def exec_loop(program : Compiler::Program, stmt : Int32, while_true : Bool, cont : Value? -> Nil) : Nil
      return if @halted
      head = program.arg(stmt, 0)
      cond = program.arg(head, 1)
      body = body_of(program, stmt)
      exit_loop = ->(v : Value?) do
        @break_stack.pop?
        cont.call(v)
      end
      @break_stack << exit_loop
      loop_check(program, cond, body, while_true, exit_loop)
    end

    private def loop_check(program : Compiler::Program, cond : Int32, body : Array(Int32), while_true : Bool, exit_loop : Value? -> Nil) : Nil
      return if @halted
      eval(program, cond) do |v|
        next if @halted
        test = truthy?(v) == while_true
        tick(@step_costs.branch) do
          next if @halted
          if test
            exec_body(program, body, 0, 0.as(Value), ->(_last : Value) { loop_check(program, cond, body, while_true, exit_loop) })
          else
            exit_loop.call(nil)
          end
        end
      end
    end

    private def exec_case(program : Compiler::Program, stmt : Int32, cont : Value? -> Nil) : Nil
      return if @halted
      kids = program.children(stmt)
      eval(program, program.arg(kids[0], 1)) do |subject|
        next if @halted
        exec_case_seq(program, kids, 1, subject, false, false, nil, cont)
      end
    end

    private def exec_case_seq(program : Compiler::Program, kids : Array(Int32), index : Int32, subject : Value, taken : Bool, done : Bool, result : Value?, cont : Value? -> Nil) : Nil
      return if @halted
      if index >= kids.size
        cont.call(result)
        return
      end
      k = kids[index]
      case program.type(k)
      when Type::WhenHead
        if done
          cont.call(result)
          return
        end
        eval(program, program.arg(k, 1)) do |wv|
          next if @halted
          is_taken = wv == subject
          tick(@step_costs.branch) do
            next if @halted
            exec_case_seq(program, kids, index + 1, subject, is_taken, done || is_taken, result, cont)
          end
        end
      when Type::ElseKeyword
        if done
          cont.call(result)
        else
          exec_case_seq(program, kids, index + 1, subject, true, true, result, cont)
        end
      when Type::Statement
        if taken
          exec(program, k) do |v|
            next if @halted
            exec_case_seq(program, kids, index + 1, subject, taken, done, v, cont)
          end
        else
          exec_case_seq(program, kids, index + 1, subject, taken, done, result, cont)
        end
      else
        exec_case_seq(program, kids, index + 1, subject, taken, done, result, cont)
      end
    end

    # ---- expressions ----

    private def eval(program : Compiler::Program, i : Int32, &cont : Value -> Nil) : Nil
      return if @halted
      n = program[i]
      case n.rule
      when :lex
        eval_leaf(program, i, cont)
      when :literal
        literal_value : Value = program.type(program.arg(i, 0)) == Type::TrueKeyword ? 1 : 0
        tick(@step_costs.fetch) { cont.call(literal_value) }
      when :paren
        eval(program, program.arg(i, 1), &cont)
      when :neg
        eval(program, program.arg(i, 1)) do |inner|
          next if @halted
          if iv = int(inner)
            tick(@step_costs.operator) { cont.call(0 &- iv) }
          end
        end
      when :mul, :add, :cmp, :eq, :and, :or
        eval(program, program.arg(i, 0)) do |l|
          next if @halted
          eval(program, program.arg(i, 2)) do |r|
            next if @halted
            if v = binop(program.type(program.arg(i, 1)), l, r)
              tick(@step_costs.operator) { cont.call(v) }
            end
          end
        end
      when :assign
        eval(program, program.arg(i, 2)) do |value|
          next if @halted
          tick(@step_costs.store) { cont.call(assign(program.lexeme(program.arg(i, 0)), value)) }
        end
      when :opassign
        name = program.lexeme(program.arg(i, 0))
        op = case program.type(program.arg(i, 1))
             when Type::AddAssign then Type::AddOperator
             when Type::SubAssign then Type::SubOperator
             when Type::MulAssign then Type::MulOperator
             else                      Type::ModOperator
             end
        eval(program, program.arg(i, 2)) do |r|
          next if @halted
          if v = binop(op, lookup(name), r)
            tick(@step_costs.fetch + @step_costs.operator + @step_costs.store) { cont.call(assign(name, v)) }
          end
        end
      when :call0
        tick(@step_costs.builtin) { builtin(program.lexeme(i), [] of Value, cont) }
      when :call1, :command1, :call2, :command2
        kids = program.children(i)
        args = kids[1..].reject { |k| program.type(k).in?(Type::OpenParen, Type::CloseParen, Type::Comma) }
        eval_args(program, args, 0, [] of Value) do |values|
          next if @halted
          tick(@step_costs.builtin) { builtin(program.lexeme(kids[0]), values, cont) }
        end
      when :call
        kids = program.children(i)
        args = kids[2..].reject { |k| program.type(k).in?(Type::CloseParen, Type::Comma) }
        eval_args(program, args, 0, [] of Value) do |values|
          next if @halted
          tick(@step_costs.call) { call_user(program, program.lexeme(kids[0]), values, cont) }
        end
      else
        runtime_error("cannot evaluate #{n.rule}")
      end
    end

    private def eval_args(program : Compiler::Program, args : Array(Int32), index : Int32, acc : Array(Value), &cont : Array(Value) -> Nil) : Nil
      return if @halted
      if index >= args.size
        cont.call(acc)
        return
      end
      eval(program, args[index]) do |v|
        next if @halted
        eval_args(program, args, index + 1, acc + [v], &cont)
      end
    end

    private def eval_leaf(program : Compiler::Program, i : Int32, cont : Value -> Nil) : Nil
      return if @halted
      n = program[i]
      case n.type
      when Type::Number
        tick(@step_costs.fetch) { cont.call(program.value(n).to_i32) }
      when Type::String
        tick(@step_costs.fetch) { cont.call(program.value(n)[1...-1]) }
      when Type::Identifier
        identifier(program, program.value(n), cont)
      when Type::ZeroArgMethod
        tick(@step_costs.builtin) { builtin(program.value(n), [] of Value, cont) }
      else
        runtime_error("#{n.type} is not a value")
      end
    end

    private def identifier(program : Compiler::Program, name : String, cont : Value -> Nil) : Nil
      return if @halted
      if defined_var?(name)
        tick(@step_costs.fetch) { cont.call(lookup(name)) }
      elsif @functions.has_key?(name)
        tick(@step_costs.call) { call_user(program, name, [] of Value, cont) }
      else
        runtime_error("undefined variable or function #{name}")
      end
    end

    private def defined_var?(name : String) : Bool
      (@frames.last?.try(&.has_key?(name)) || false) || @globals.has_key?(name) || @constants.has_key?(name)
    end

    private def lookup(name : String) : Value
      if (frame = @frames.last?) && frame.has_key?(name)
        frame[name]
      elsif @globals.has_key?(name)
        @globals[name]
      elsif @constants.has_key?(name)
        @constants[name]
      else
        0
      end
    end

    private def assign(name : String, value : Value) : Value
      if @globals.has_key?(name)
        @globals[name] = value
      elsif (frame = @frames.last?)
        frame[name] = value
      else
        @constants[name] = value
      end
      value
    end

    private def truthy?(v : Value) : Bool
      v.is_a?(String) || v != 0
    end

    private def int(v : Value) : Int32?
      return v if v.is_a?(Int32)
      runtime_error("expected a number, got #{v.inspect}")
      nil
    end

    private def binop(op : Type, l : Value, r : Value) : Value?
      a = int(l)
      return nil if a.nil?
      b = int(r)
      return nil if b.nil?
      case op
      when Type::AddOperator then a &+ b
      when Type::SubOperator then a &- b
      when Type::MulOperator then a &* b
      when Type::FloorDivOperator, Type::DivOperator
        b == 0 ? 0 : (b == -1 ? 0 &- a : a // b)
      when Type::ModOperator
        b == 0 || b == -1 ? 0 : a % b
      when Type::EqOperator  then a == b ? 1 : 0
      when Type::NeOperator  then a != b ? 1 : 0
      when Type::LtOperator  then a < b ? 1 : 0
      when Type::GtOperator  then a > b ? 1 : 0
      when Type::LeOperator  then a <= b ? 1 : 0
      when Type::GeOperator  then a >= b ? 1 : 0
      when Type::AndOperator then a != 0 && b != 0 ? 1 : 0
      when Type::OrOperator  then a != 0 || b != 0 ? 1 : 0
      when Type::XorOperator then a ^ b
      else
        runtime_error("unknown operator #{op}")
        nil
      end
    end

    private def builtin(name : String, args : Array(Value), cont : Value -> Nil) : Nil
      return if @halted
      host = @host
      if host.nil?
        runtime_error("no host")
        return
      end
      case name
      when "puts"
        host.puts(args[0])
        cont.call(0)
      when "damage" then cont.call(host.damage)
      when "speed"  then cont.call(host.speed)
      when "loc_x"  then cont.call(host.loc_x)
      when "loc_y"  then cont.call(host.loc_y)
      when "sleep"  then cont.call(host.sleep)
      when "rand"
        if a = int(args[0])
          cont.call(host.rand(a))
        end
      when "sqrt"
        if a = int(args[0])
          cont.call(host.sqrt(a))
        end
      when "sin"
        if a = int(args[0])
          cont.call(host.sin(a))
        end
      when "cos"
        if a = int(args[0])
          cont.call(host.cos(a))
        end
      when "tan"
        if a = int(args[0])
          cont.call(host.tan(a))
        end
      when "atan"
        if a = int(args[0])
          cont.call(host.atan(a))
        end
      when "scan"
        if (a = int(args[0])) && (b = int(args[1]))
          cont.call(host.scan(a, b))
        end
      when "cannon"
        if (a = int(args[0])) && (b = int(args[1]))
          cont.call(host.cannon(a, b))
        end
      when "drive"
        if (a = int(args[0])) && (b = int(args[1]))
          cont.call(host.drive(a, b))
        end
      else
        runtime_error("unknown builtin #{name}")
      end
    end

    # Charges exactly one cycle and pauses -- unless `n <= 0`, nothing to
    # charge, run straight through. The pause is `@resume`: a closure that
    # re-enters here with `n - 1` and the same `after`, so a `tick(n)` call
    # (a builtin costs 2, a call costs 3, and so on) still pauses once per
    # unit, matching `field.cr`'s fiber granularity (whose `on_step` hook
    # likewise charges `@cycles` once per unit, not once per `tick` call).
    private def tick(n : Int32, &after : -> Nil) : Nil
      return if @halted
      if n <= 0
        after.call
        return
      end
      @cycles += 1
      remaining = n - 1
      @resume = -> { tick(remaining, &after) }
    end
  end

  class Field
    # `run`'s non-fiber twin: drives every robot with `Robot#step!`
    # instead of `Robot#cycle`, otherwise identical (same physics, same
    # frame recording, same cycle/motion accounting). Kept as a separate
    # method rather than a flag on `run` so the fiber path -- the CLI, and
    # every other spec in this suite -- is untouched by this file. Used by
    # `src/browser.cr`'s `crd_battle` (compiled for wasm32-unknown-wasi,
    # where fibers are not trusted) and, natively, by the differential
    # spec that proves the wasm32 build agrees with it: both run this
    # exact method, so "agrees" is guaranteed by construction, not by
    # reproducing `run`'s own fiber-based scheduling cycle for cycle.
    def run_stepwise : self
      @robots.each(&.start_stepwise)
      if (positions = @positions)
        positions.each_with_index { |(x, y), i| place(i, x, y) if i < @robots.size }
      else
        rand_pos
      end
      record(0)
      movement = MOTION_CYCLES
      c = 0_i64
      every = Math.max(1_i64, (@limit // MOTION_CYCLES) // @max_frames)
      updates = 0_i64
      while active.size > 1 && c < @limit
        @robots.each { |r| r.step! if r.active }
        movement -= 1
        if movement == 0
          c += MOTION_CYCLES
          movement = MOTION_CYCLES
          move_robots
          move_missiles
          count_missiles
          updates += 1
          record(c) if updates % every == 0
        end
      end
      guard = 0
      while @robots.any? { |r| r.missiles.any? { |m| m.stat.flying? } } && guard < 100
        c += MOTION_CYCLES
        move_robots
        move_missiles
        count_missiles
        guard += 1
      end
      @cycles = c
      record(c)
      self
    end
  end
end
