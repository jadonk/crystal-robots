require "./program"
require "./parser"

# The semantic pass, run after the parser and before the emitter or the
# interpreter: syntax alone cannot tell an undefined variable, a call with
# the wrong number of arguments, a `return` outside a function, a `break`
# outside a loop, or two `def`s with the same name, from a program that
# means something. `Checker.check(program)` collects every such problem
# it finds, each with its source location, instead of stopping at the
# first one.
module CrystalRobots::Compiler
  class Checker
    struct Issue
      getter message : String, line : Int32, col : Int32

      def initialize(@message : String, @line : Int32, @col : Int32)
      end

      def to_s(io : IO) : Nil
        io << message << " at " << line << ':' << col
      end
    end

    # Per-statement checking context: the names in scope as locals (a
    # function's parameters and anything assigned anywhere in its body,
    # empty at the top level and inside `main`), and whether `return`
    # and `break` are currently valid.
    private record Scope, locals : Set(String), in_function : Bool, in_loop : Bool

    def self.check(program : Program) : Array(Issue)
      new(program).issues
    end

    getter issues = [] of Issue

    def initialize(@program : Program)
      @globals = Set(String).new
      @arity = {} of String => Int32
      collect_declarations
      top = Scope.new(Set(String).new, in_function: false, in_loop: false)
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def
          check_function(stmt)
        when :main
          body_of(stmt).each { |s| check_statement(s, top) }
        else
          check_statement(stmt, top)
        end
      end
    end

    private def issue(i : Int32, message : String) : Nil
      line, col = @program.location(i)
      @issues << Issue.new(message, line, col)
    end

    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    # `def` names and arities, flagging a repeat; `global` names. Run
    # before any statement is checked, so a function may call another
    # defined later in the source.
    private def collect_declarations : Nil
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :global
          @globals << @program.value(@program.arg(stmt, 2))
        when :def
          head = @program.children(stmt)[0]
          idents = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
          name = @program.lexeme(idents[0])
          issue(idents[0], "#{name} is already defined") if @arity.has_key?(name)
          @arity[name] = idents.size - 1
        when :exprstmt
          # A plain top-level assignment (`C1X = 10`) is an implicit
          # global too, the shape the example robots use for constants.
          expr = @program.arg(stmt, 0)
          @globals << @program.value(@program.arg(expr, 0)) if @program[expr].rule == :assign
        end
      end
    end

    private def check_function(stmt : Int32) : Nil
      head = @program.arg(stmt, 0)
      idents = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
      params = idents[1..].map { |i| @program.lexeme(i) }
      locals = params.to_set
      body_of(stmt).each { |s| locals.concat(assigned_names(s)) }
      scope = Scope.new(locals, in_function: true, in_loop: false)
      body_of(stmt).each { |s| check_statement(s, scope) }
    end

    # Every name a statement, or anything nested inside it, assigns to --
    # the only place an identifier used as a value can come from besides a
    # parameter or a global, since assignment is always a whole statement
    # (`docs/PARSER.md`'s lookahead ties it to the newline right after).
    private def assigned_names(stmt : Int32) : Array(String)
      names = [] of String
      case @program[stmt].rule
      when :exprstmt
        expr = @program.arg(stmt, 0)
        names << @program.value(@program.arg(expr, 0)) if @program[expr].rule == :assign
      when :while, :until
        body_of(stmt).each { |s| names.concat(assigned_names(s)) }
      when :if
        @program.children(stmt).each { |k| names.concat(assigned_names(k)) if @program.type(k) == Type::Statement }
      end
      names
    end

    private def check_statement(stmt : Int32, scope : Scope) : Nil
      case @program[stmt].rule
      when :global
        check_expression(@program.arg(stmt, 4), scope)
      when :exprstmt
        check_expression(@program.arg(stmt, 0), scope)
      when :return
        issue(stmt, "return outside of a function") unless scope.in_function
        kids = @program.children(stmt)
        check_expression(kids[1], scope) if kids.size > 2
      when :break
        issue(stmt, "break outside of a loop") unless scope.in_loop
      when :while, :until
        head = @program.children(stmt)[0]
        check_expression(@program.arg(head, 1), scope)
        inner = Scope.new(scope.locals, scope.in_function, in_loop: true)
        body_of(stmt).each { |s| check_statement(s, inner) }
      when :if
        @program.children(stmt).each do |k|
          case @program.type(k)
          when Type::IfHead, Type::ElsifHead
            check_expression(@program.arg(k, 1), scope)
          when Type::Statement
            check_statement(k, scope)
          end
        end
      end
    end

    private def check_expression(i : Int32, scope : Scope) : Nil
      n = @program[i]
      case n.rule
      when :lex
        if n.type == Type::Identifier
          name = @program.value(n)
          known = scope.locals.includes?(name) || @globals.includes?(name) || @arity[name]? == 0
          issue(i, "undefined variable #{name}") unless known
        end
      when :assign
        check_expression(@program.arg(i, 2), scope)
      when :paren, :neg
        check_expression(@program.arg(i, 1), scope)
      when :mul, :add, :cmp, :eq
        check_expression(@program.arg(i, 0), scope)
        check_expression(@program.arg(i, 2), scope)
      when :command1, :call1
        check_expression(@program.arg(i, n.rule == :call1 ? 2 : 1), scope)
      when :command2, :call2
        a, b = n.rule == :call2 ? {2, 4} : {1, 3}
        check_expression(@program.arg(i, a), scope)
        check_expression(@program.arg(i, b), scope)
      when :call
        kids = @program.children(i)
        name = @program.lexeme(kids[0])
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        if (arity = @arity[name]?)
          issue(i, "#{name} takes #{arity} argument#{"s" if arity != 1}, given #{args.size}") if arity != args.size
        else
          issue(i, "undefined function #{name}")
        end
        args.each { |a| check_expression(a, scope) }
      end
    end
  end
end
