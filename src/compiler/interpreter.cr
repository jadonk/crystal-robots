require "./program"
require "./parser"

# A tree-walking reference interpreter over the same AST `WASM_Emitter`
# compiles, integer-only, sharing its truncating `/ // %` for now (see
# `WASM_Emitter`'s comment on the same point). Every builtin goes through
# `Host`, the seam a real battlefield will implement later; `NullHost` is
# a deterministic stand-in with the same behavior the WASM specs bind
# their own stand-in host to, so the two engines can be run against each
# other on the same robot and checked for the same output.
module CrystalRobots::Compiler
  abstract class Host
    abstract def puts(n : Int32) : Int32
    abstract def scan(angle : Int32, resolution : Int32) : Int32
    abstract def cannon(angle : Int32, range : Int32) : Int32
    abstract def drive(heading : Int32, speed : Int32) : Int32
    abstract def damage : Int32
    abstract def speed : Int32
    abstract def loc_x : Int32
    abstract def loc_y : Int32
    abstract def sleep : Int32
    abstract def rand(n : Int32) : Int32
    abstract def sqrt(n : Int32) : Int32
    abstract def sin(n : Int32) : Int32
    abstract def cos(n : Int32) : Int32
    abstract def tan(n : Int32) : Int32
    abstract def atan(n : Int32) : Int32
  end

  # No battlefield exists yet: the sensors return fixed, distinct values,
  # the two-argument builtins return the sum of their arguments, and the
  # math builtins do real degree-based trigonometry. `puts` collects into
  # `puts_out`.
  class NullHost < Host
    getter puts_out = [] of Int32

    def puts(n : Int32) : Int32
      @puts_out << n
      n
    end

    def scan(angle : Int32, resolution : Int32) : Int32
      angle + resolution
    end

    def cannon(angle : Int32, range : Int32) : Int32
      angle + range
    end

    def drive(heading : Int32, speed : Int32) : Int32
      heading + speed
    end

    def damage : Int32
      11
    end

    def speed : Int32
      22
    end

    def loc_x : Int32
      33
    end

    def loc_y : Int32
      44
    end

    def sleep : Int32
      55
    end

    def rand(n : Int32) : Int32
      n
    end

    def sqrt(n : Int32) : Int32
      Math.sqrt(n).to_i32
    end

    def sin(n : Int32) : Int32
      Math.sin(n.to_f * Math::PI / 180).round.to_i32
    end

    def cos(n : Int32) : Int32
      Math.cos(n.to_f * Math::PI / 180).round.to_i32
    end

    def tan(n : Int32) : Int32
      Math.tan(n.to_f * Math::PI / 180).round.to_i32
    end

    def atan(n : Int32) : Int32
      (Math.atan(n.to_f) * 180 / Math::PI).round.to_i32
    end
  end

  # Behaves exactly like `NullHost` -- there is still no battlefield -- but
  # also echoes every `puts` to the console, for the CLI's `-i`.
  class ConsoleHost < NullHost
    def puts(n : Int32) : Int32
      STDOUT.puts n
      super
    end
  end

  class Interpreter
    # Every builtin name `builtin0`/`builtin1`/`builtin2` below actually
    # dispatch, in one place: spec-checked against those three `case`
    # statements (spec/interpreter_spec.cr) and against
    # Web::RobotAPI::ENTRIES's keys, so a builtin can never go
    # undocumented and a documented name can never be make-believe.
    BUILTIN_NAMES = %w(
      damage speed loc_x loc_y sleep
      puts rand sqrt sin cos tan atan
      scan cannon drive
    )

    # How many cycles each kind of work costs, the same units CROBOTS
    # charged per bytecode instruction, mapped onto this tree-walker's
    # coarser AST-node granularity: a fetch or a store is one instruction
    # in either machine, an operator is one BINOP, a builtin call folds
    # the intrinsic dispatch and its bogus-frame cleanup into one weight,
    # and a user call folds pushing arguments and the FCALL into another.
    # `Costs.statements` is the simplest possible model -- one per
    # statement executed, everything else free -- kept for comparisons
    # that only care about how many statements ran.
    class Costs
      property fetch = 1
      property operator = 1
      property store = 1
      property builtin = 2
      property call = 3
      property branch = 1
      property statement = 1

      def self.statements : Costs
        c = new
        c.fetch = c.operator = c.store = c.builtin = c.call = c.branch = 0
        c
      end
    end

    private class BreakSignal < Exception
    end

    private class ReturnSignal < Exception
      getter value : Int32

      def initialize(@value : Int32)
      end
    end

    private class Scope
      property locals = {} of String => Int32
    end

    def self.execute(program : Program, host : Host, costs : Costs = Costs.new) : Int64
      i = new(program, host, costs)
      i.run
      i.cycles
    end

    getter cycles = 0_i64

    # When both are set, `sync_step` is called once per statement executed
    # and once per loop-condition check -- covering an empty loop body
    # too, so a bare `while true` still cooperates -- letting a scheduler
    # interleave several robots' interpreters, each in its own Fiber, one
    # step at a time: send on `done_channel` (blocks until the scheduler
    # is ready to collect it), then receive from `step_channel` (blocks
    # until the scheduler permits the next step). `nil` by default: every
    # existing caller runs a robot to completion in one call, unaffected.
    #
    # This is deliberately not bare `Fiber.yield`: Crystal's own fiber
    # scheduler does not guarantee a `Fiber.yield` call hands control
    # back to whichever fiber called `resume` (confirmed by hand -- a
    # tight `Fiber.new`/`resume`/`Fiber.yield` loop ran a fiber to
    # completion in one `resume` instead of pausing at each `yield`); a
    # `Channel` round-trip is the concurrency primitive Crystal actually
    # guarantees ordering for.
    property step_channel : Channel(Nil)?
    property done_channel : Channel(Nil)?

    def initialize(@program : Program, @host : Host, @costs : Costs = Costs.new)
      @globals = {} of String => Int32
      @functions = {} of String => Int32
      @arity = {} of String => Int32
      # A static pass, matching `WASM_Emitter`'s: every `global(...)` and
      # every plain top-level assignment (the shape the example robots use
      # for constants, `C1X = 10`) declares a global up front, at 0, so a
      # function reads the same set of globals no matter what has run yet.
      body_of(@program.root).each do |stmt|
        case @program[stmt].rule
        when :global
          @globals[@program.value(@program.arg(stmt, 2))] = 0
        when :def
          head = @program.children(stmt)[0]
          idents = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
          name = @program.lexeme(idents[0])
          @functions[name] = stmt
          @arity[name] = idents.size - 1
        when :exprstmt
          expr = @program.arg(stmt, 0)
          if @program[expr].rule == :assign
            name = @program.value(@program.arg(expr, 0))
            @globals[name] = 0 unless @globals.has_key?(name)
          end
        end
      end
    end

    def run : Nil
      main_stmts = [] of Int32
      scope = Scope.new
      body_of(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def
        when :main
          main_stmts = body_of(stmt)
        else
          exec_statement(stmt, scope)
        end
      end
      main_stmts.each { |s| exec_statement(s, scope) }
    end

    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    private def charge(n : Int32) : Nil
      @cycles += n
    end

    private def sync_step : Nil
      d = @done_channel
      s = @step_channel
      return unless d && s
      d.send(nil)
      s.receive
    end

    # The value of a statement is the value of its expression, or, for
    # `if`, whichever branch's last statement ran; a loop is not a value
    # and yields 0, matching `WASM_Emitter`'s reset of `Ctx#ret`.
    private def exec_statement(stmt : Int32, scope : Scope) : Int32
      charge(@costs.statement)
      sync_step
      case @program[stmt].rule
      when :global
        @globals[@program.value(@program.arg(stmt, 2))] = eval(@program.arg(stmt, 4), scope)
      when :exprstmt
        return eval(@program.arg(stmt, 0), scope)
      when :while
        loop_exec(stmt, scope, while_true: true)
      when :until
        loop_exec(stmt, scope, while_true: false)
      when :break
        charge(@costs.branch)
        raise BreakSignal.new
      when :return
        charge(@costs.branch)
        kids = @program.children(stmt)
        raise ReturnSignal.new(kids.size > 2 ? eval(kids[1], scope) : 0)
      when :if
        return if_exec(stmt, scope)
      when :case
        return case_exec(stmt, scope)
      end
      0
    end

    private def loop_exec(stmt : Int32, scope : Scope, while_true : Bool) : Nil
      head = @program.children(stmt)[0]
      cond = @program.arg(head, 1)
      loop do
        value = eval(cond, scope)
        charge(@costs.branch)
        sync_step
        keep_going = while_true ? value != 0 : value == 0
        break unless keep_going
        begin
          body_of(stmt).each { |s| exec_statement(s, scope) }
        rescue BreakSignal
          break
        end
      end
    end

    private def if_exec(stmt : Int32, scope : Scope) : Int32
      branches = [] of {Int32?, Array(Int32)}
      @program.children(stmt).each do |k|
        case @program.type(k)
        when Type::IfHead, Type::ElsifHead
          branches << {@program.arg(k, 1), [] of Int32}
        when Type::ElseKeyword
          branches << {nil, [] of Int32}
        when Type::Statement
          branches.last[1] << k
        end
      end
      branches.each do |(cond, stmts)|
        if cond
          value = eval(cond, scope)
          charge(@costs.branch)
          next if value == 0
        end
        result = 0
        stmts.each { |s| result = exec_statement(s, scope) }
        return result
      end
      0
    end

    private def case_exec(stmt : Int32, scope : Scope) : Int32
      kids = @program.children(stmt)
      subject = eval(@program.arg(kids[0], 1), scope)
      branches = [] of {Int32?, Array(Int32)}
      kids.each do |k|
        case @program.type(k)
        when Type::WhenHead
          branches << {@program.arg(k, 1), [] of Int32}
        when Type::ElseKeyword
          branches << {nil, [] of Int32}
        when Type::Statement
          branches.last[1] << k
        end
      end
      branches.each do |(cond, stmts)|
        if cond
          value = eval(cond, scope)
          charge(@costs.branch)
          next if value != subject
        end
        result = 0
        stmts.each { |s| result = exec_statement(s, scope) }
        return result
      end
      0
    end

    # An identifier in value position: a variable fetch, or -- if it is
    # not a variable at all -- a call to a zero-parameter function, the
    # `run`/`change`/`new_corner` style bare calls the example robots use.
    # Charges its own cost (call or fetch) rather than the fixed fetch
    # `eval`'s :lex case charges a plain number literal with.
    private def identifier_get(name : String, scope : Scope) : Int32
      if !scope.locals.has_key?(name) && !@globals.has_key?(name) && @arity[name]? == 0
        value = call_function(name, [] of Int32)
        charge(@costs.call)
        value
      else
        charge(@costs.fetch)
        scope.locals[name]? || @globals[name]? || raise "undefined variable #{name}"
      end
    end

    # Store into a variable and return the value: a global that already
    # exists goes there unless shadowed by a local of the same name,
    # otherwise it is a local, first assignment introducing it.
    private def set_variable(name : String, value : Int32, scope : Scope) : Int32
      if @globals.has_key?(name) && !scope.locals.has_key?(name)
        @globals[name] = value
      else
        scope.locals[name] = value
      end
      value
    end

    private def call_function(name : String, args : Array(Int32)) : Int32
      stmt = @functions[name]? || raise "undefined function #{name}"
      head = @program.arg(stmt, 0)
      params = @program.children(head).select { |i| @program.type(i) == Type::Identifier }[1..].map { |i| @program.lexeme(i) }
      scope = Scope.new
      params.each_with_index { |p, idx| scope.locals[p] = args[idx] }
      result = 0
      begin
        body_of(stmt).each { |s| result = exec_statement(s, scope) }
      rescue e : ReturnSignal
        result = e.value
      end
      result
    end

    def eval(i : Int32, scope : Scope) : Int32
      n = @program[i]
      case n.rule
      when :lex
        if n.type == Type::Identifier
          identifier_get(@program.value(n), scope)
        else
          charge(@costs.fetch)
          @program.value(n).to_i32
        end
      when :literal
        charge(@costs.fetch)
        @program.type(@program.arg(i, 0)) == Type::TrueKeyword ? 1 : 0
      when :assign
        name = @program.value(@program.arg(i, 0))
        value = eval(@program.arg(i, 2), scope)
        charge(@costs.store)
        set_variable(name, value, scope)
      when :opassign
        name = @program.value(@program.arg(i, 0))
        opt = case @program.type(@program.arg(i, 1))
              when Type::AddAssign then Type::AddOperator
              when Type::SubAssign then Type::SubOperator
              when Type::MulAssign then Type::MulOperator
              else                      Type::ModOperator
              end
        old = scope.locals[name]? || @globals[name]? || raise "undefined variable #{name}"
        value = binary(opt, old, eval(@program.arg(i, 2), scope))
        charge(@costs.fetch + @costs.operator + @costs.store)
        set_variable(name, value, scope)
      when :paren
        eval(@program.arg(i, 1), scope)
      when :neg
        value = -eval(@program.arg(i, 1), scope)
        charge(@costs.operator)
        value
      when :mul, :add, :cmp, :eq, :and, :or
        value = binary(@program.type(@program.arg(i, 1)), eval(@program.arg(i, 0), scope), eval(@program.arg(i, 2), scope))
        charge(@costs.operator)
        value
      when :call0
        value = builtin0(@program.lexeme(i))
        charge(@costs.builtin)
        value
      when :command1, :call1
        arg_index = n.rule == :call1 ? 2 : 1
        value = builtin1(@program.lexeme(@program.arg(i, 0)), eval(@program.arg(i, arg_index), scope))
        charge(@costs.builtin)
        value
      when :command2, :call2
        a, b = n.rule == :call2 ? {2, 4} : {1, 3}
        value = builtin2(@program.lexeme(@program.arg(i, 0)), eval(@program.arg(i, a), scope), eval(@program.arg(i, b), scope))
        charge(@costs.builtin)
        value
      when :call
        kids = @program.children(i)
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        value = call_function(@program.lexeme(kids[0]), args.map { |a| eval(a, scope) })
        charge(@costs.call)
        value
      else
        raise "expression #{n.rule} is not supported by the interpreter"
      end
    end

    private def binary(opt : Type, left : Int32, right : Int32) : Int32
      case opt
      when Type::AddOperator then left + right
      when Type::SubOperator then left - right
      when Type::MulOperator then left * right
      when Type::DivOperator, Type::FloorDivOperator
        left.tdiv(right)
      when Type::ModOperator then left.remainder(right)
      when Type::EqOperator  then left == right ? 1 : 0
      when Type::NeOperator  then left != right ? 1 : 0
      when Type::LtOperator  then left < right ? 1 : 0
      when Type::GtOperator  then left > right ? 1 : 0
      when Type::LeOperator  then left <= right ? 1 : 0
      when Type::GeOperator  then left >= right ? 1 : 0
      when Type::AndOperator then left != 0 && right != 0 ? 1 : 0
      when Type::OrOperator  then left != 0 || right != 0 ? 1 : 0
      when Type::XorOperator then left ^ right
      else
        raise "operator #{opt} is not supported by the interpreter"
      end
    end

    private def builtin0(name : String) : Int32
      case name
      when "damage" then @host.damage
      when "speed"  then @host.speed
      when "loc_x"  then @host.loc_x
      when "loc_y"  then @host.loc_y
      when "sleep"  then @host.sleep
      else
        raise "undefined builtin #{name}"
      end
    end

    private def builtin1(name : String, a : Int32) : Int32
      case name
      when "puts" then @host.puts(a)
      when "rand" then @host.rand(a)
      when "sqrt" then @host.sqrt(a)
      when "sin"  then @host.sin(a)
      when "cos"  then @host.cos(a)
      when "tan"  then @host.tan(a)
      when "atan" then @host.atan(a)
      else
        raise "undefined builtin #{name}"
      end
    end

    private def builtin2(name : String, a : Int32, b : Int32) : Int32
      case name
      when "scan"   then @host.scan(a, b)
      when "cannon" then @host.cannon(a, b)
      when "drive"  then @host.drive(a, b)
      else
        raise "undefined builtin #{name}"
      end
    end
  end
end
