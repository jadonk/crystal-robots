# The progressive multipass tokenizer.
#
# Pass 0 turns the source text into a glyph string with the lexical rules.
# Every later pass applies exactly one grammar rule, a regex over glyphs, to
# the whole string: the first rule in `GRAMMAR` order that matches anywhere
# is applied to every non-overlapping match, each match collapsing to a
# single new glyph. The next pass starts again from the top of the list, so
# higher-precedence rules always win. Parsing ends when no rule matches;
# success is the single Program glyph `⏹`.
#
# See `docs/PARSER.md` for the reasoning behind the rule order and the
# lookaround guards.
module CrystalRobots::Compiler
  class Parser
    class Error < Exception
      getter line : Int32, col : Int32

      def initialize(message : String, @line : Int32, @col : Int32)
        super("#{message} at #{@line}:#{@col}")
      end
    end

    # One grammar rule: a regex over glyphs and the glyph it reduces to.
    struct Rule
      getter name : Symbol, regex : Regex, type : Type

      def initialize(@name : Symbol, @regex : Regex, @type : Type)
      end
    end

    KEYWORDS = {
      "begin" => Type::BeginKeyword, "break" => Type::BreakKeyword, "case" => Type::CaseKeyword,
      "def" => Type::DefKeyword, "do" => Type::DoKeyword, "else" => Type::ElseKeyword,
      "elsif" => Type::ElsifKeyword, "end" => Type::EndKeyword, "false" => Type::FalseKeyword,
      "for" => Type::ForKeyword, "if" => Type::IfKeyword, "in" => Type::InKeyword,
      "next" => Type::NextKeyword, "nil" => Type::NilKeyword, "require" => Type::RequireKeyword,
      "then" => Type::ThenKeyword, "true" => Type::TrueKeyword, "while" => Type::WhileKeyword,
      "until" => Type::UntilKeyword, "when" => Type::WhenKeyword, "return" => Type::ReturnKeyword,
      "main" => Type::MainKeyword, "global" => Type::GlobalKeyword,
      "damage" => Type::ZeroArgMethod, "speed" => Type::ZeroArgMethod, "loc_x" => Type::ZeroArgMethod,
      "loc_y" => Type::ZeroArgMethod, "sleep" => Type::ZeroArgMethod,
      "puts" => Type::OneArgMethod, "rand" => Type::OneArgMethod, "sqrt" => Type::OneArgMethod,
      "sin" => Type::OneArgMethod, "cos" => Type::OneArgMethod, "tan" => Type::OneArgMethod,
      "atan" => Type::OneArgMethod,
      "scan" => Type::TwoArgMethod, "cannon" => Type::TwoArgMethod, "drive" => Type::TwoArgMethod,
    }

    OPERATORS = {
      "==" => Type::EqOperator, "!=" => Type::NeOperator, "<=" => Type::LeOperator,
      ">=" => Type::GeOperator, "&&" => Type::AndOperator, "||" => Type::OrOperator,
      "+=" => Type::AddAssign, "-=" => Type::SubAssign, "*=" => Type::MulAssign,
      "%=" => Type::ModAssign, "//" => Type::FloorDivOperator,
      "+" => Type::AddOperator, "-" => Type::SubOperator, "*" => Type::MulOperator,
      "/" => Type::DivOperator, "%" => Type::ModOperator, "<" => Type::LtOperator,
      ">" => Type::GtOperator, "&" => Type::AndOperator, "|" => Type::OrOperator,
      "^" => Type::XorOperator, "=" => Type::Assign, "(" => Type::OpenParen,
      ")" => Type::CloseParen, "," => Type::Comma,
    }

    # Pass 0 rules, tried in order at the current text position. A nil type
    # drops the match. Operators and words are looked up in the tables.
    LEXICAL = [
      {/\A#[^\n]*/, nil},
      {/\A[ \t\r]+/, nil},
      {/\A(\n|;)+/, Type::Newline},
      {/\A"[^"]*"/, Type::String},
      {/\A[0-9]+/, Type::Number},
      {/\A(==|!=|<=|>=|&&|\|\||\+=|-=|\*=|%=|\/\/|[-+*\/%<>=&|^(),])/, Type::Invalid},
      {/\A[A-Za-z_][A-Za-z0-9_]*/, Type::Identifier},
    ]

    # Anything that is already a value: number, string, expression, identifier.
    V = "[№🐍😑𝑥]"

    # Infix operator glyphs by precedence level, tightest first.
    MULOPS = "⊗／⊘％"
    ADDOPS = "⊕⊖"
    CMPOPS = "≺≻≼≽"
    EQOPS  = "≟≠"
    ANDOPS = "∧"
    OROPS  = "∨⊻"

    # An infix rule at level L reduces `V op V` only when the left operand is
    # not preceded by an operator of level <= L (that operand belongs to the
    # earlier operator, giving left associativity) and the right operand is
    # not followed by an operator of level < L (that operand belongs to the
    # tighter operator).
    def self.infix(ops : String, higher : String) : Regex
      ahead = higher.empty? ? "" : "(?![#{higher}])"
      Regex.new("(?<![#{higher}#{ops}])#{V}[#{ops}]#{V}#{ahead}")
    end

    # Grammar rules in priority order. Each pass applies the FIRST rule in
    # this list that matches anywhere, to every non-overlapping match.
    GRAMMAR = [
      # headers first: a def or main header must never be read as a call
      Rule.new(:main_head, /🏁⟮🐍⟯🔖⏎/, Type::MainHead),
      Rule.new(:def_head, /🔕𝑥(⟮(𝑥(，𝑥)*)?⟯)?⏎/, Type::DefHead),
      Rule.new(:global, /🌐⟮𝑥，#{V}⟯⏎/, Type::Statement),
      # values
      Rule.new(:literal, /[🔢🔚]/, Type::Expression),
      Rule.new(:call0, /∉/, Type::Expression),
      Rule.new(:call, /𝑥⟮(#{V}(，#{V})*)?⟯/, Type::Expression),
      Rule.new(:call1, /∊⟮#{V}⟯/, Type::Expression),
      Rule.new(:call2, /∋⟮#{V}，#{V}⟯/, Type::Expression),
      Rule.new(:paren, /⟮#{V}⟯/, Type::Expression),
      Rule.new(:neg, /(?<![№🐍😑𝑥⟯])⊖#{V}/, Type::Expression),
      # infix, tightest first
      Rule.new(:mul, infix(MULOPS, ""), Type::Expression),
      Rule.new(:add, infix(ADDOPS, MULOPS), Type::Expression),
      Rule.new(:cmp, infix(CMPOPS, MULOPS + ADDOPS), Type::Expression),
      Rule.new(:eq, infix(EQOPS, MULOPS + ADDOPS + CMPOPS), Type::Expression),
      Rule.new(:and, infix(ANDOPS, MULOPS + ADDOPS + CMPOPS + EQOPS), Type::Expression),
      Rule.new(:or, infix(OROPS, MULOPS + ADDOPS + CMPOPS + EQOPS + ANDOPS), Type::Expression),
      # command calls without parentheses bind loosest of all expressions
      Rule.new(:command1, /∊#{V}(?=[⏎⟯，])/, Type::Expression),
      Rule.new(:command2, /∋#{V}，#{V}(?=[⏎⟯，])/, Type::Expression),
      # assignment is right associative: only once the value is complete
      Rule.new(:assign, /𝑥＝#{V}(?=[⏎⟯，])/, Type::Expression),
      Rule.new(:opassign, /𝑥[➕➖✖⁒]#{V}(?=[⏎⟯，])/, Type::Expression),
      # block headers
      Rule.new(:if_head, /🔜#{V}⏎/, Type::IfHead),
      Rule.new(:elsif_head, /🔘#{V}⏎/, Type::ElsifHead),
      Rule.new(:while_head, /🔣#{V}⏎/, Type::WhileHead),
      Rule.new(:until_head, /🔂#{V}⏎/, Type::UntilHead),
      Rule.new(:case_head, /🔔#{V}⏎/, Type::CaseHead),
      Rule.new(:when_head, /🔶#{V}⏎/, Type::WhenHead),
      # simple statements
      Rule.new(:return, /↩#{V}?⏎/, Type::Statement),
      Rule.new(:break, /🔓⏎/, Type::Statement),
      Rule.new(:exprstmt, /#{V}⏎/, Type::Statement),
      # blocks reduce only once their body is entirely statements
      Rule.new(:if, /🅸❢*(🅴❢*)*(🔗⏎❢*)?🔙⏎/, Type::Statement),
      Rule.new(:while, /🆆❢*🔙⏎/, Type::Statement),
      Rule.new(:until, /🆄❢*🔙⏎/, Type::Statement),
      Rule.new(:case, /🅲(🆂❢*)+(🔗⏎❢*)?🔙⏎/, Type::Statement),
      Rule.new(:def, /🅳❢*🔙⏎/, Type::Statement),
      Rule.new(:main, /🅼❢*🔙⏎/, Type::Statement),
      Rule.new(:program, /\A❢+\z/, Type::Program),
    ]

    property program : Program

    # Parse `src` completely. Raises `Parser::Error` with a source location
    # when the text cannot be reduced to a program.
    def initialize(src : String = "")
      @program = Program.new(src)
      Parser.parse(@program)
    end

    # Work budgets. Every pass re-emits the glyphs it did not reduce, so the
    # total number of glyphs emitted is the parser's cost; a long operator
    # chain reduces one glyph per pass and would otherwise cost the square of
    # its length. CROBOTS capped a robot at 1000 machine instructions; two
    # million glyphs is a few hundred passes over a robot several times the
    # size of the largest example, and well under a second of work.
    class_property max_passes = 20_000
    class_property max_glyphs = 2_000_000

    # Raises `Error` on a bad source; `try_parse` is the same logic without
    # the raise, for callers -- `wasm32-unknown-wasi` battles among them,
    # see `src/battle/step_robot.cr` -- that cannot let one bad robot's
    # `raise` take the whole call down with it (Crystal has no working
    # exception handling on that target at all: a `raise`, even rescued in
    # the very same function, traps the module instead of unwinding).
    def self.parse(p : Program) : Program
      if (err = try_parse(p))
        raise err
      end
      p
    end

    # `parse`'s logic, returning the `Error` instead of raising it (or
    # `nil` on success) so a caller can report it as data.
    def self.try_parse(p : Program) : Error?
      if (err = try_lex(p))
        return err
      end
      if p.current.empty?
        # an empty source is an empty program
        idx = p.push(Type::Program, p.source.size, 0, 1, :program)
        p.add_pass([idx], :program)
        return nil
      end
      while reduce_once(p)
        # a budget error points at the parser's most recent reduction
        if p.passes > max_passes
          line, col = p.location(p.size - 1)
          return Error.new("Program needs more than #{max_passes} passes", line, col)
        end
        if p.emitted > max_glyphs
          line, col = p.location(p.size - 1)
          return Error.new("Program is too large to parse (more than #{max_glyphs} glyphs of work)", line, col)
        end
      end
      unless p.parsed?
        bad = p.current.find { |i| p.type(i) != Type::Statement } || p.current[0]
        line, col = p.location(bad)
        return Error.new("Cannot reduce #{p.type(bad).glyph} (#{p.type(bad)}) in #{p}", line, col)
      end
      nil
    end

    # Pass 0. Returns the glyph string.
    def self.lex(p : Program) : String
      if (err = try_lex(p))
        raise err
      end
      p.to_s
    end

    # `lex`'s logic, returning the `Error` instead of raising it.
    def self.try_lex(p : Program) : Error?
      text = p.text
      layer = [] of Int32
      pos = 0
      while pos < text.size
        rest = text[pos..]
        matched = false
        LEXICAL.each do |(regex, type)|
          m = regex.match(rest)
          next unless m
          matched = true
          lexeme = m[0]
          t = type
          if t == Type::Invalid
            t = OPERATORS[lexeme]
          elsif t == Type::Identifier
            t = KEYWORDS.fetch(lexeme, Type::Identifier)
          end
          if t && !(t == Type::Newline && (layer.empty? || p.type(layer.last) == Type::Newline))
            layer << p.push(t, pos, lexeme.size, 0, :lex)
          end
          pos += lexeme.size
          break
        end
        unless matched
          line, col = p.line_col(pos)
          return Error.new("Unexpected character #{text[pos].inspect}", line, col)
        end
      end
      # end of input terminates the last statement
      unless layer.empty? || p.type(layer.last) == Type::Newline
        layer << p.push(Type::Newline, text.size, 0, 0, :lex)
      end
      p.add_pass(layer, :lex)
      nil
    end

    # One reduction pass. Returns false when no rule matches.
    def self.reduce_once(p : Program) : Bool
      layer = p.current
      s = p.glyphs(layer)
      base = p.pass.last
      level = p.passes
      GRAMMAR.each do |rule|
        matches = s.scan(rule.regex)
        next if matches.empty?
        next_layer = [] of Int32
        cursor = 0
        matches.each do |m|
          b = m.begin(0)
          len = m[0].size
          (cursor...b).each { |i| next_layer << layer[i] }
          next_layer << p.push(rule.type, base + b, len, level, rule.name)
          cursor = b + len
        end
        (cursor...layer.size).each { |i| next_layer << layer[i] }
        p.add_pass(next_layer, rule.name)
        return true
      end
      false
    end
  end
end
