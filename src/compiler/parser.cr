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
# See docs/PARSER.md for the reasoning; this commit implements just enough
# of it to parse one or more `puts NUMBER` statements.
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

    KEYWORDS = {"puts" => Type::OneArgMethod}

    # Pass 0 rules, tried in order at the current text position. `:skip`
    # drops the match (whitespace); `:word` looks the lexeme up in
    # `KEYWORDS`.
    LEXICAL = [
      {/\A[ \t\r]+/, :skip},
      {/\A(\n|;)+/, :newline},
      {/\A[0-9]+/, :number},
      {/\A[A-Za-z_][A-Za-z0-9_]*/, :word},
    ]

    # Grammar rules in priority order. Each pass applies the FIRST rule in
    # this list that matches anywhere, to every non-overlapping match.
    GRAMMAR = [
      Rule.new(:command1, /∊№/, Type::Expression),
      Rule.new(:exprstmt, /😑⏎/, Type::Statement),
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
          when :word
            t = KEYWORDS[lexeme]? || raise Error.new("Unexpected word #{lexeme.inspect}")
            layer << p.push(t, pos, lexeme.size, 0, :lex)
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
