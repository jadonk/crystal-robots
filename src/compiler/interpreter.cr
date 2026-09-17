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

  class Interpreter
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

    def self.execute(program : Program, host : Host) : Nil
      new(program, host).run
    end

    def initialize(@program : Program, @host : Host)
      @globals = {} of String => Int32
      @functions = {} of String => Int32
    end

    def run : Nil
      main_stmts = [] of Int32
      scope = Scope.new
      body_of(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def
          head = @program.children(stmt)[0]
          idents = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
          @functions[@program.lexeme(idents[0])] = stmt
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

    # The value of a statement is the value of its expression, or, for
    # `if`, whichever branch's last statement ran; a loop is not a value
    # and yields 0, matching `WASM_Emitter`'s reset of `Ctx#ret`.
    private def exec_statement(stmt : Int32, scope : Scope) : Int32
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
        raise BreakSignal.new
      when :return
        kids = @program.children(stmt)
        raise ReturnSignal.new(kids.size > 2 ? eval(kids[1], scope) : 0)
      when :if
        return if_exec(stmt, scope)
      end
      0
    end

    private def loop_exec(stmt : Int32, scope : Scope, while_true : Bool) : Nil
      head = @program.children(stmt)[0]
      cond = @program.arg(head, 1)
      loop do
        keep_going = while_true ? eval(cond, scope) != 0 : eval(cond, scope) == 0
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
        next unless cond.nil? || eval(cond, scope) != 0
        result = 0
        stmts.each { |s| result = exec_statement(s, scope) }
        return result
      end
      0
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
        return @program.value(n).to_i32 unless n.type == Type::Identifier
        name = @program.value(n)
        scope.locals[name]? || @globals[name]? || raise "undefined variable #{name}"
      when :assign
        name = @program.value(@program.arg(i, 0))
        value = eval(@program.arg(i, 2), scope)
        if @globals.has_key?(name) && !scope.locals.has_key?(name)
          @globals[name] = value
        else
          scope.locals[name] = value
        end
        value
      when :paren
        eval(@program.arg(i, 1), scope)
      when :neg
        -eval(@program.arg(i, 1), scope)
      when :mul, :add, :cmp, :eq
        binary(@program.type(@program.arg(i, 1)), eval(@program.arg(i, 0), scope), eval(@program.arg(i, 2), scope))
      when :call0
        builtin0(@program.lexeme(i))
      when :command1
        builtin1(@program.lexeme(@program.arg(i, 0)), eval(@program.arg(i, 1), scope))
      when :command2
        builtin2(@program.lexeme(@program.arg(i, 0)), eval(@program.arg(i, 1), scope), eval(@program.arg(i, 3), scope))
      when :call
        kids = @program.children(i)
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        call_function(@program.lexeme(kids[0]), args.map { |a| eval(a, scope) })
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
