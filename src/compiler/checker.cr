# Semantic checks on a parsed program, run before it executes so a typo
# shows up as a located message instead of a runtime restart loop.
#
# Checks: every identifier read is a parameter, a variable assigned earlier
# in the same function (textual order), a global, a constant, or a function
# with no parameters; every user call names a function and passes the right
# number of arguments; `return` only inside `def`; `break` only inside a
# loop; a function is defined once.
module CrystalRobots::Compiler
  class Checker
    record Problem, message : String, line : Int32, col : Int32 do
      def to_s(io : IO)
        io << message << " at " << line << ':' << col
      end
    end

    getter problems = [] of Problem

    # Function name to parameter count.
    getter functions = {} of String => Int32

    def self.check(program : Program) : Array(Problem)
      new(program).run
    end

    def initialize(@program : Program)
      @globals = Set(String).new
      @constants = Set(String).new
    end

    def run : Array(Problem)
      top = @program.children(@program.root)
      # declarations first, so order of definition does not matter
      top.each do |stmt|
        case @program[stmt].rule
        when :def
          head = @program.arg(stmt, 0)
          names = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
          name = @program.lexeme(names[0])
          problem("function #{name} is defined twice", names[0]) if @functions.has_key?(name)
          @functions[name] = names.size - 1
        when :global
          @globals << @program.lexeme(@program.children(stmt)[2])
        when :exprstmt
          expr = @program.arg(stmt, 0)
          @constants << @program.lexeme(@program.arg(expr, 0)) if @program[expr].rule == :assign
        end
      end
      top.each do |stmt|
        case @program[stmt].rule
        when :def
          head = @program.arg(stmt, 0)
          params = @program.children(head).select { |i| @program.type(i) == Type::Identifier }[1..].map { |i| @program.lexeme(i) }
          check_body(body_of(stmt), Set(String).new(params), in_def: true, in_loop: false)
        when :global
          check_expr(@program.children(stmt)[4], Set(String).new, in_def: false)
        when :main
          check_body(body_of(stmt), Set(String).new, in_def: false, in_loop: false)
        else
          check_stmt(stmt, Set(String).new, in_def: false, in_loop: false)
        end
      end
      @problems
    end

    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    private def problem(message : String, node : Int32) : Nil
      line, col = @program.location(node)
      @problems << Problem.new(message, line, col)
    end

    private def check_body(stmts : Array(Int32), locals : Set(String), in_def : Bool, in_loop : Bool) : Nil
      stmts.each { |s| check_stmt(s, locals, in_def, in_loop) }
    end

    private def check_stmt(stmt : Int32, locals : Set(String), in_def : Bool, in_loop : Bool) : Nil
      case @program[stmt].rule
      when :exprstmt
        check_expr(@program.arg(stmt, 0), locals, in_def)
      when :return
        problem("return outside of a def", stmt) unless in_def
        kids = @program.children(stmt)
        check_expr(kids[1], locals, in_def) if kids.size > 2
      when :break
        problem("break outside of a loop", stmt) unless in_loop
      when :if, :case
        @program.children(stmt).each do |k|
          case @program.type(k)
          when Type::IfHead, Type::ElsifHead, Type::CaseHead, Type::WhenHead
            check_expr(@program.arg(k, 1), locals, in_def)
          when Type::Statement
            check_stmt(k, locals, in_def, in_loop)
          end
        end
      when :while, :until
        check_expr(@program.arg(@program.arg(stmt, 0), 1), locals, in_def)
        check_body(body_of(stmt), locals, in_def, true)
      when :global
        @globals << @program.lexeme(@program.children(stmt)[2])
        check_expr(@program.children(stmt)[4], locals, in_def)
      when :def
        problem("def inside a block is not supported", stmt)
      end
    end

    private def check_expr(i : Int32, locals : Set(String), in_def : Bool) : Nil
      n = @program[i]
      case n.rule
      when :lex
        if n.type == Type::Identifier
          name = @program.value(n)
          return if locals.includes?(name) || @globals.includes?(name) || @constants.includes?(name)
          if (arity = @functions[name]?)
            problem("#{name} takes #{arity} arguments but is called with none", i) unless arity == 0
            return
          end
          problem("undefined variable or function #{name}", i)
        end
      when :assign, :opassign
        name = @program.lexeme(@program.arg(i, 0))
        if n.rule == :opassign && !(locals.includes?(name) || @globals.includes?(name) || @constants.includes?(name))
          problem("undefined variable #{name}", @program.arg(i, 0))
        end
        check_expr(@program.arg(i, 2), locals, in_def)
        locals << name unless @globals.includes?(name) || @constants.includes?(name)
      when :call
        kids = @program.children(i)
        name = @program.lexeme(kids[0])
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        if (arity = @functions[name]?)
          problem("#{name} takes #{arity} arguments but is called with #{args.size}", kids[0]) unless arity == args.size
        else
          problem("undefined function #{name}", kids[0])
        end
        args.each { |a| check_expr(a, locals, in_def) }
      else
        @program.children(i).each do |k|
          check_expr(k, locals, in_def) if @program[k].level > 0 || @program.type(k) == Type::Identifier
        end
      end
    end
  end
end
