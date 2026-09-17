require "./program"

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
# See docs/PARSER.md for the reasoning; this commit adds `if`/`elsif`/`else`
# to the comparisons, loops and globals of the previous ones.
module CrystalRobots::Compiler
  class Parser
    class Error < Exception
    end

    # One grammar rule: a regex over glyphs and the glyph it reduces to.
    struct Rule
      getter name : Symbol, regex : Regex, type : Type

      def initialize(@name : Symbol, @regex : Regex, @type : Type)
      end
    end

    KEYWORDS = {
      "puts" => Type::OneArgMethod, "global" => Type::GlobalKeyword,
      "while" => Type::WhileKeyword, "until" => Type::UntilKeyword,
      "end" => Type::EndKeyword, "break" => Type::BreakKeyword,
      "if" => Type::IfKeyword, "elsif" => Type::ElsifKeyword, "else" => Type::ElseKeyword,
    }

    OPERATORS = {
      "//" => Type::FloorDivOperator, "==" => Type::EqOperator, "!=" => Type::NeOperator,
      "<=" => Type::LeOperator, ">=" => Type::GeOperator,
      "+" => Type::AddOperator, "-" => Type::SubOperator, "*" => Type::MulOperator,
      "/" => Type::DivOperator, "%" => Type::ModOperator, "=" => Type::Assign,
      "<" => Type::LtOperator, ">" => Type::GtOperator,
      "(" => Type::OpenParen, ")" => Type::CloseParen, "," => Type::Comma,
    }

    # Pass 0 rules, tried in order at the current text position. `:skip`
    # drops the match (whitespace); `:word` looks the lexeme up in
    # `KEYWORDS`, falling back to an identifier; `:operator` looks it up in
    # `OPERATORS`.
    LEXICAL = [
      {/\A[ \t\r]+/, :skip},
      {/\A(\n|;)+/, :newline},
      {/\A[0-9]+/, :number},
      {/\A(\/\/|==|!=|<=|>=|[-+*\/%(),=<>])/, :operator},
      {/\A[A-Za-z_][A-Za-z0-9_]*/, :word},
    ]

    # Anything that is already a value: a number, an identifier, or a
    # reduced expression.
    V = "[№𝑥😑]"

    # Infix operator glyphs by precedence level, tightest first.
    MULOPS = "⊗／⊘％"
    ADDOPS = "⊕⊖"
    CMPOPS = "≺≻≼≽"
    EQOPS  = "≟≠"

    # An infix rule at level L reduces `V op V` only when the left operand
    # is not preceded by an operator of level <= L (that operand belongs to
    # the earlier operator, giving left associativity) and the right
    # operand is not followed by an operator of a tighter level (that
    # operand belongs to the tighter operator instead). See docs/PARSER.md
    # section 2 for the full reasoning.
    def self.infix(ops : String, higher : String) : Regex
      ahead = higher.empty? ? "" : "(?![#{higher}])"
      Regex.new("(?<![#{higher}#{ops}])#{V}[#{ops}]#{V}#{ahead}")
    end

    # Grammar rules in priority order. Each pass applies the FIRST rule in
    # this list that matches anywhere, to every non-overlapping match.
    GRAMMAR = [
      # a global header must never be read as anything else
      Rule.new(:global, /🌐⟮𝑥，#{V}⟯⏎/, Type::Statement),
      Rule.new(:paren, /⟮#{V}⟯/, Type::Expression),
      Rule.new(:neg, /(?<![№𝑥😑⟯])⊖#{V}/, Type::Expression),
      Rule.new(:mul, infix(MULOPS, ""), Type::Expression),
      Rule.new(:add, infix(ADDOPS, MULOPS), Type::Expression),
      Rule.new(:cmp, infix(CMPOPS, MULOPS + ADDOPS), Type::Expression),
      Rule.new(:eq, infix(EQOPS, MULOPS + ADDOPS + CMPOPS), Type::Expression),
      Rule.new(:command1, /∊#{V}(?=[⏎⟯])/, Type::Expression),
      # assignment is right associative: only once the value is complete
      Rule.new(:assign, /𝑥＝#{V}(?=⏎)/, Type::Expression),
      # block headers
      Rule.new(:if_head, /🔜#{V}⏎/, Type::IfHead),
      Rule.new(:elsif_head, /🔘#{V}⏎/, Type::ElsifHead),
      Rule.new(:while_head, /🔣#{V}⏎/, Type::WhileHead),
      Rule.new(:until_head, /🔂#{V}⏎/, Type::UntilHead),
      # simple statements
      Rule.new(:break, /🔓⏎/, Type::Statement),
      Rule.new(:exprstmt, /#{V}⏎/, Type::Statement),
      # blocks reduce only once their body is entirely statements
      Rule.new(:if, /🅸❢*(🅴❢*)*(🔗⏎❢*)?🔙⏎/, Type::Statement),
      Rule.new(:while, /🆆❢*🔙⏎/, Type::Statement),
      Rule.new(:until, /🆄❢*🔙⏎/, Type::Statement),
      Rule.new(:program, /\A❢+\z/, Type::Program),
    ]

    property program : Program

    # Parse `src` completely. Raises `Parser::Error` when the text cannot
    # be reduced to a program.
    def initialize(src : String = "")
      @program = Program.new(src)
      Parser.parse(@program)
    end

    def self.parse(p : Program) : Program
      lex(p)
      while reduce_once(p)
      end
      unless p.parsed?
        raise Error.new("Cannot reduce #{p.glyphs(p.current)}")
      end
      p
    end

    # Pass 0. Returns the glyph string.
    def self.lex(p : Program) : String
      text = p.text
      layer = [] of Int32
      pos = 0
      while pos < text.size
        rest = text[pos..]
        matched = false
        LEXICAL.each do |(regex, action)|
          m = regex.match(rest)
          next unless m
          matched = true
          lexeme = m[0]
          case action
          when :skip
            # whitespace: nothing to push
          when :newline
            unless layer.empty? || p.type(layer.last) == Type::Newline
              layer << p.push(Type::Newline, pos, lexeme.size, 0, :lex)
            end
          when :number
            layer << p.push(Type::Number, pos, lexeme.size, 0, :lex)
          when :operator
            layer << p.push(OPERATORS[lexeme], pos, lexeme.size, 0, :lex)
          when :word
            layer << p.push(KEYWORDS.fetch(lexeme, Type::Identifier), pos, lexeme.size, 0, :lex)
          end
          pos += lexeme.size
          break
        end
        raise Error.new("Unexpected character #{text[pos].inspect}") unless matched
      end
      unless layer.empty? || p.type(layer.last) == Type::Newline
        layer << p.push(Type::Newline, text.size, 0, 0, :lex)
      end
      p.add_pass(layer, :lex)
      p.glyphs(layer)
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
          b = m.begin(0).not_nil!
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
