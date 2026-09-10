# Reference interpreter: walks the parsed `Program` and executes it with
# integer semantics. Robot builtins go through a `Host`, so the same
# program runs against a stub, the battlefield simulation, or (later) the
# same interface the WebAssembly imports bind to.
module CrystalRobots::Compiler
  # The robot's view of the world. Every builtin the language exposes is a
  # method here; the interpreter, the native prelude and the WASM imports
  # all target this one interface.
  abstract class Host
    abstract def scan(degree : Int32, resolution : Int32) : Int32
    abstract def cannon(degree : Int32, range : Int32) : Int32
    abstract def drive(degree : Int32, speed : Int32) : Int32
    abstract def damage : Int32
    abstract def speed : Int32
    abstract def loc_x : Int32
    abstract def loc_y : Int32
    abstract def sleep : Int32
    abstract def rand(limit : Int32) : Int32

    # Called for every `puts`.
    def puts(value : Value) : Nil
    end

    def sqrt(n : Int32) : Int32
      Math.isqrt(n.abs).to_i32
    end

    def sin(degree : Int32) : Int32
      (Math.sin(degree * Math::PI / 180) * 100000).to_i32
    end

    def cos(degree : Int32) : Int32
      (Math.cos(degree * Math::PI / 180) * 100000).to_i32
    end

    def tan(degree : Int32) : Int32
      (Math.tan(degree * Math::PI / 180) * 100000).to_i32
    end

    def atan(ratio : Int32) : Int32
      (Math.atan(ratio / 100000.0) * 180 / Math::PI).to_i32
    end
  end

  # A host with no battlefield: sensors read zero, actuators do nothing,
  # `rand` is seeded so runs are reproducible.
  class NullHost < Host
    def initialize(seed : UInt64 = 1_u64)
      @random = Random.new(seed)
    end

    def scan(degree : Int32, resolution : Int32) : Int32
      0
    end

    def cannon(degree : Int32, range : Int32) : Int32
      0
    end

    def drive(degree : Int32, speed : Int32) : Int32
      0
    end

    def damage : Int32
      0
    end

    def speed : Int32
      0
    end

    def loc_x : Int32
      0
    end

    def loc_y : Int32
      0
    end

    def sleep : Int32
      0
    end

    def rand(limit : Int32) : Int32
      limit <= 0 ? 0 : @random.rand(limit)
    end
  end

  class Interpreter
    class RuntimeError < Exception
    end

    # Raised when the step budget is used up; the caller decides what a
    # step means (a cycle limit for the CLI, a fairness slice for battles).
    class StepLimit < Exception
    end

    private class BreakSignal < Exception
    end

    private class ReturnSignal < Exception
      getter value : Value

      def initialize(@value : Value)
        super("return")
      end
    end

    # A user function: its parameter names and the statement nodes of its body.
    private record Function, params : Array(String), body : Array(Int32)

    @@puts_out = [] of String

    # Everything `puts` wrote since `puts_clear`, one line per call.
    def self.puts_out : String
      @@puts_out.join("\n")
    end

    def self.puts_clear : Nil
      @@puts_out = [] of String
    end

    # Run a parsed program to completion. Returns 0.
    def self.execute(p : Program, host : Host = NullHost.new) : Int32
      new(p, host).run
    end

    getter program : Program, host : Host, steps : Int32

    # Called on every step. The battlefield uses it to hand control back to
    # the scheduler between robots (see `Battle::Robot`).
    property on_step : Proc(Nil)? = nil

    def initialize(@program : Program, @host : Host = NullHost.new, @step_limit : Int32 = 1_000_000)
      @globals = {} of String => Value
      @constants = {} of String => Value
      @functions = {} of String => Function
      @frames = [] of Hash(String, Value)
      @steps = 0
    end

    def run : Int32
      main_body = nil
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def    then define(stmt)
        when :global then declare_global(stmt)
        when :main   then main_body = body_of(stmt)
        else              exec_top(stmt)
        end
      end
      if main_body
        @frames << {} of String => Value
        begin
          main_body.each { |s| exec(s) }
        rescue ReturnSignal
        ensure
          @frames.pop
        end
      end
      0
    end

    # Top-level statements outside `main`: constants and plain statements.
    private def exec_top(stmt : Int32) : Nil
      expr = @program.arg(stmt, 0)
      if @program[stmt].rule == :exprstmt && @program[expr].rule == :assign
        name = @program.lexeme(@program.arg(expr, 0))
        @constants[name] = eval(@program.arg(expr, 2))
      else
        @frames << @constants
        begin
          exec(stmt)
        ensure
          @frames.pop
        end
      end
    end

    private def define(stmt : Int32) : Nil
      head = @program.arg(stmt, 0)
      names = @program.children(head).select { |i| @program.type(i) == Type::Identifier }.map { |i| @program.lexeme(i) }
      @functions[names[0]] = Function.new(names[1..], body_of(stmt))
    end

    private def declare_global(stmt : Int32) : Nil
      kids = @program.children(stmt) # 🌐 ⟮ 𝑥 ， V ⟯ ⏎
      @globals[@program.lexeme(kids[2])] = eval(kids[4])
    end

    # The statement children of a block node (everything that is a ❢).
    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    private def step : Nil
      @steps += 1
      raise StepLimit.new("step limit #{@step_limit} reached") if @steps > @step_limit
      if (hook = @on_step)
        hook.call
      end
    end

    private def truthy?(v : Value) : Bool
      v.is_a?(String) || v != 0
    end

    # Execute one statement. Returns the value of an expression statement so
    # a function body can return its last expression.
    def exec(stmt : Int32) : Value?
      step
      n = @program[stmt]
      case n.rule
      when :exprstmt
        eval(@program.arg(stmt, 0))
      when :return
        kids = @program.children(stmt)
        raise ReturnSignal.new(kids.size > 2 ? eval(kids[1]) : 0)
      when :break
        raise BreakSignal.new("break")
      when :if
        exec_if(stmt)
      when :while
        exec_loop(stmt, true)
      when :until
        exec_loop(stmt, false)
      when :case
        exec_case(stmt)
      when :global
        declare_global(stmt)
        nil
      when :def
        define(stmt)
        nil
      else
        raise RuntimeError.new("cannot execute #{n.rule}")
      end
    end

    private def exec_if(stmt : Int32) : Value?
      taken = false
      result = nil
      @program.children(stmt).each do |k|
        case @program.type(k)
        when Type::IfHead, Type::ElsifHead
          break if taken
          taken = truthy?(eval(@program.arg(k, 1)))
        when Type::ElseKeyword
          break if taken
          taken = true
        when Type::Statement
          result = exec(k) if taken
        end
      end
      result
    end

    private def exec_loop(stmt : Int32, while_true : Bool) : Value?
      head = @program.arg(stmt, 0)
      cond = @program.arg(head, 1)
      body = body_of(stmt)
      begin
        loop do
          step # an empty loop body must still consume the step budget
          break unless truthy?(eval(cond)) == while_true
          body.each { |s| exec(s) }
        end
      rescue BreakSignal
      end
      nil
    end

    private def exec_case(stmt : Int32) : Value?
      kids = @program.children(stmt)
      subject = eval(@program.arg(kids[0], 1))
      taken = false
      done = false
      result = nil
      kids[1..].each do |k|
        case @program.type(k)
        when Type::WhenHead
          break if done
          taken = eval(@program.arg(k, 1)) == subject
          done = true if taken
        when Type::ElseKeyword
          break if done
          taken = true
          done = true
        when Type::Statement
          result = exec(k) if taken
        end
      end
      result
    end

    # Evaluate an expression node.
    def eval(i : Int32) : Value
      n = @program[i]
      case n.rule
      when :lex
        eval_leaf(i)
      when :literal
        @program.type(@program.arg(i, 0)) == Type::TrueKeyword ? 1 : 0
      when :paren
        eval(@program.arg(i, 1))
      when :neg
        0 - int(eval(@program.arg(i, 1)))
      when :mul, :add, :cmp, :eq, :and, :or
        binop(@program.type(@program.arg(i, 1)), eval(@program.arg(i, 0)), eval(@program.arg(i, 2)))
      when :assign
        assign(@program.lexeme(@program.arg(i, 0)), eval(@program.arg(i, 2)))
      when :opassign
        name = @program.lexeme(@program.arg(i, 0))
        op = case @program.type(@program.arg(i, 1))
             when Type::AddAssign then Type::AddOperator
             when Type::SubAssign then Type::SubOperator
             when Type::MulAssign then Type::MulOperator
             else                      Type::ModOperator
             end
        assign(name, binop(op, lookup(name), eval(@program.arg(i, 2))))
      when :call0
        builtin(@program.lexeme(i), [] of Value)
      when :call1, :command1, :call2, :command2
        kids = @program.children(i)
        args = kids[1..].reject { |k| {Type::OpenParen, Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        builtin(@program.lexeme(kids[0]), args.map { |k| eval(k) })
      when :call
        kids = @program.children(i)
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        call(@program.lexeme(kids[0]), args.map { |k| eval(k) })
      else
        raise RuntimeError.new("cannot evaluate #{n.rule}")
      end
    end

    private def eval_leaf(i : Int32) : Value
      n = @program[i]
      case n.type
      when Type::Number     then @program.value(n).to_i32
      when Type::String     then @program.value(n)[1...-1]
      when Type::Identifier then identifier(@program.value(n))
      when Type::ZeroArgMethod
        builtin(@program.value(n), [] of Value)
      else
        raise RuntimeError.new("#{n.type} is not a value")
      end
    end

    # A bare identifier is a variable, a constant, or a call to a
    # zero-parameter function.
    private def identifier(name : String) : Value
      return lookup(name) if defined?(name)
      return call(name, [] of Value) if @functions.has_key?(name)
      raise RuntimeError.new("undefined variable or function #{name}")
    end

    private def defined?(name : String) : Bool
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
        raise RuntimeError.new("undefined variable #{name}")
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

    private def int(v : Value) : Int32
      v.is_a?(Int32) ? v : raise RuntimeError.new("expected a number, got #{v.inspect}")
    end

    private def binop(op : Type, l : Value, r : Value) : Value
      a = int(l)
      b = int(r)
      case op
      when Type::AddOperator then a &+ b
      when Type::SubOperator then a &- b
      when Type::MulOperator then a &* b
      when Type::FloorDivOperator, Type::DivOperator
        b == 0 ? 0 : a // b # CROBOTS returns 0 on division by zero
      when Type::ModOperator
        b == 0 ? 0 : a % b
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
        raise RuntimeError.new("unknown operator #{op}")
      end
    end

    private def call(name : String, args : Array(Value)) : Value
      fn = @functions[name]? || raise RuntimeError.new("undefined function #{name}")
      if fn.params.size != args.size
        raise RuntimeError.new("#{name} expects #{fn.params.size} arguments, got #{args.size}")
      end
      frame = {} of String => Value
      fn.params.each_with_index { |param, k| frame[param] = args[k] }
      @frames << frame
      result = 0.as(Value)
      begin
        fn.body.each { |s| result = exec(s) || 0 }
      rescue ret : ReturnSignal
        result = ret.value
      ensure
        @frames.pop
      end
      result
    end

    private def builtin(name : String, args : Array(Value)) : Value
      case name
      when "puts"
        @@puts_out << args[0].to_s
        @host.puts(args[0])
        0
      when "damage" then @host.damage
      when "speed"  then @host.speed
      when "loc_x"  then @host.loc_x
      when "loc_y"  then @host.loc_y
      when "sleep"  then @host.sleep
      when "rand"   then @host.rand(int(args[0]))
      when "sqrt"   then @host.sqrt(int(args[0]))
      when "sin"    then @host.sin(int(args[0]))
      when "cos"    then @host.cos(int(args[0]))
      when "tan"    then @host.tan(int(args[0]))
      when "atan"   then @host.atan(int(args[0]))
      when "scan"   then @host.scan(int(args[0]), int(args[1]))
      when "cannon" then @host.cannon(int(args[0]), int(args[1]))
      when "drive"  then @host.drive(int(args[0]), int(args[1]))
      else
        raise RuntimeError.new("unknown builtin #{name}")
      end
    end
  end
end
