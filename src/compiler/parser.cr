# TODO: Write documentation for `CrystalRobots::Compiler::Parser`
#
# Let's see if the doc tool allows more sophisticated markdown here
#
# I ultimately want to end up with an array of statments. Statements will typically have
# arguments at previous levels.
#
# OK, I think I've figured out what the difference between a parser and a tokenizer is. A
# parser is just going to call the tokenizer repeatedly, but after the first time, you need
# a function to determine something looking back at the token array from the earlier pass.
#
# I don't think I can express a grammar with my regex match thingy though unless I make
# the tokens unique. I think that means I need to make my token types utilize an index
# offset.
#
# https://en.wikipedia.org/wiki/Abstract_syntax_tree
#
# ```
# bottom (0): [[ type : Type, value : String, line, column, [..args..]], ...]
#        (1): [[ type : Type, .., [index0_in_0, index1_in_0, ...]], ...]
#    top (n): [[ type : Type = Statement, .., [..args..]], ...]
# ```

module CrystalRobots::Compiler
  class Parser
    def initialize(source : String)
      @program = Program.new
    end

    def self.new(source : String)
      program = Program.new
      src = source
      while src != "⏹" && src != ""
        Log.d "tokenize(#{program.pc.pass}, #{src})"
        t = tokenize(program, src)
        program.add_pass(t)
        src = tokens_to_s(t)
      end
      i = Parser.allocate
      i.program = program
      i
    end

    def program
      @program
    end

    def program=(@program : Program)
    end

    struct Matcher
      property r, t, phase

      def initialize(@r : Regex, @t : Type, @phase : Int32)
      end
    end

    struct TokenDef
      property v, s, h, r

      def initialize(@v : Array(Tuple(String, Type)) | Nil, @s : String, @h : Hash(String, Type), @r : Regex | Nil)
      end

      def initialize(values : Array(Tuple(String, Type)))
        @v = values
        @s = (values.map { |s, t| Regex.escape(s) }).join("|")
        @h = Hash(String, Type).new
        @v.each_index do |i|
          @h[values[i][0]] = values[i][1]
        end
        @r = Regex.new("^(#{@s})")
      end

      # All tokens are the same type, so copy to each
      def initialize(type : Type, values : Array(String))
        t_values = [] of Tuple(String, Type)
        values.each_index do |i|
          t_values.push({values[i], type})
        end
        initialize(t_values)
      end

      def initialize(t : Nil)
        @v = nil
        @s = ""
        @h = Hash(String,Type)
        @r = nil
      end
    end

    enum MappingType
      Default
      Expression
      Program
    end

    struct GrammarRule
      property rule

      def initialize(@rule : Tuple(Regex | Nil, Array(TokenDef) | Nil, Type, MappingType))
      end

      def initialize(rs : Tuple(Regex | Nil, Array(Tuple(String, Type)) | Nil, Type, MappingType))
        token_defs = Array(TokenDef)
        rs[1].each do |r|
          if rs[0].nil?
            token_defs = 
          else
            token_defs = 
          end
        @rule = {r[0], token_defs, r[2], r[3]}
      end
    end

    class Grammar
      property grammar

      def initialize(@grammar : Array(GrammarRule))
      end

      def self.new
        i = Grammar.allocate
        i.grammar = [] of GrammarRule
        i
      end

      def <<(r : GrammarRule) : self # Tuple(Regex | Nil, Array(Tuple(String, Type)) | Nil, Type, MappingType)) : self
        @grammar << r
      end
    end

    # These are language keywords that generate various statement types
    # I think there are 2 mechanisms for getting a token type assigned, there can
    # either be a simple pattern match, or there can be a match with a hash
    # lookup to find the token type. And then there is the matter of the mapping
    # function, but it might be possible to combine into a single mapper. I
    # think I might add a more generic regex to help foster lookups.
    #
    # The array is in rule precedence order. If a search is separated, that is the
    # primary reason it *should* be so, except that in several cases I simply
    # haven't thought of how to make the right unifying regex.
    #
    # NOTE: the parser should be protected from the random UTF-8 characters I
    # use as long as I disallow their use in identifiers and this will allow them to
    # still be used in strings
    #
    @@grammar = Grammar.new
    @@grammar << {/^\"([^\"]+)\"/, nil, Type::String, MappingType::Default}
    @@grammar << {/^(-{0,1}[\.0-9]+)/, nil, Type::Number, MappingType::Default}
    @@grammar << {/^(\(|\))/,
                  [
                    {"(", Type::OpenParen},
                    {")", Type::CloseParen},
                  ], nil, MappingType::Default}
    @@grammar << {nil,
                  [
                    {"*", Type::Operator},
                    {"//", Type::Operator},
                  ], Type::Operator, MappingType::Default}
    @@grammar << {nil,
                  [
                    {"+", Type::Operator},
                    {"-", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    }
    @@grammar << {nil,
                  [
                    {"==", Type::Operator},
                    {"!=", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    }
    @@grammar << {nil,
                  [
                    {"<", Type::Operator},
                    {">", Type::Operator},
                    {"<=", Type::Operator},
                    {">=", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    }
    @@grammar << {nil,
                  [
                    {"&", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    }
    @@grammar << {nil,
                  [
                    {"|", Type::Operator},
                    {"^", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    }
    @@grammar << {/^([a-z]+)\b/,
                  [
                    {"begin", Type::BeginKeyword},
                    {"break", Type::BreakKeyword},
                    {"case", Type::CaseKeyword},
                    {"def", Type::DefKeyword},
                    {"do", Type::DoKeyword},
                    {"else", Type::ElseKeyword},
                    {"elsif", Type::ElsifKeyword},
                    {"end", Type::EndKeyword},
                    {"false", Type::FalseKeyword},
                    {"for", Type::ForKeyword},
                    {"if", Type::IfKeyword},
                    {"in", Type::InKeyword},
                    {"next", Type::NextKeyword},
                    {"nil", Type::NilKeyword},
                    {"require", Type::RequireKeyword},
                    {"then", Type::ThenKeyword},
                    {"true", Type::TrueKeyword},
                    {"while", Type::WhileKeyword},
                    {"main", Type::TwoArgMethod},
                    {"puts", Type::OneArgMethod},
                    {"scan", Type::TwoArgMethod},
                    {"cannon", Type::TwoArgMethod},
                    {"drive", Type::TwoArgMethod},
                    {"damage", Type::ZeroArgMethod},
                    {"speed", Type::ZeroArgMethod},
                    {"loc_x", Type::ZeroArgMethod},
                    {"loc_y", Type::ZeroArgMethod},
                    {"rand", Type::OneArgMethod},
                    {"sqrt", Type::OneArgMethod},
                    {"sin", Type::OneArgMethod},
                    {"cos", Type::OneArgMethod},
                    {"tan", Type::OneArgMethod},
                    {"atan", Type::OneArgMethod},
                  ],
                  nil, MappingType::Default,
    }
    @@grammar << {/^(\s+)/, nil, Type::Whitespace, nil}
    @@grammar << {/^\#.*$/, nil, Type::Comment, nil}
    @@grammar << {/(№⊚№)/, nil, Type::Expression, MappingType::Default}
    @@grammar << {/^(∉)/, nil, Type::ZeroArgStatement, MappingType::Default}
    @@grammar << {/^(∊(№|🐍|😑))/, nil, Type::OneArgStatement, MappingType::Default}
    @@grammar << {/^(∋(№|🐍|😑)(№|🐍|😑))/, nil, Type::TwoArgStatement, MappingType::Default}
    @@grammar << {/^[❣❤❥]+$/, nil, Type::Program, MappingType::Program}

    def self.mapperDefault(p : Program, t : Type, m : Regex::MatchData, i : Array(Int32))
      value = m[0]
      if t == Type::Keyword
        t = @@keywords_h[value]
      elsif t == Type::Builtin
        t = @@builtins_h[value]
      end
      Log.d "default: #{t} #{value} #{i}"
      [Node.new(type: t, value: value, index: i)]
    end

    def self.mapperStatement(p : Program, t : Type, m : Regex::MatchData, i : Array(Int32))
      value = m[0]
      case t
      when Type::OneArgStatement
        a = [i[0], i[0] + 1]
      when Type::TwoArgStatement
        a = [i[0], i[0] + 1, i[0] + 2]
      else
        a = [i[0]]
      end
      Log.d "statment: #{t} #{value} #{a}"
      [Node.new(type: t, value: value, index: a)]
    end

    def self.mapperExpression(p : Program, t : Type, m : Regex::MatchData, i : Array(Int32))
      n = i[0]
      a = [n + 1, n, n + 2]
      value = m[0]
      Log.d "expression: #{t} #{value} #{i} @ #{m.begin(0)}"
      tokens = Array(Node).new
      m.begin(0).times do |j|
        Log.d "need to push #{m.string[j]} #{n} #{m.begin(0)} #{j}"
        n_off = n - m.begin(0) + j
        pc = PC.new(p.pc.pass - 1, n_off)
        node = p.node(pc)
        Log.d "node #{node} @ #{pc}"
        tokens << Node.new(type: Type.new(m.string[j].ord), value: node.value, index: [n_off])
      end
      tokens << Node.new(type: t, value: value, index: a)
    end

    @@mappers : Hash(Type, Proc(Program, Type, Regex::MatchData, Array(Int32), Array(Node)) | Nil)
    @@mappers = {
      Type::String           => ->mapperDefault(Program, Type, Regex::MatchData, Array(Int32)),
      Type::Number           => ->mapperDefault(Program, Type, Regex::MatchData, Array(Int32)),
      Type::Keyword          => ->mapperDefault(Program, Type, Regex::MatchData, Array(Int32)),
      Type::Builtin          => ->mapperDefault(Program, Type, Regex::MatchData, Array(Int32)),
      Type::Operator         => ->mapperDefault(Program, Type, Regex::MatchData, Array(Int32)),
      Type::Whitespace       => nil,
      Type::Comment          => nil,
      Type::Expression       => ->mapperExpression(Program, Type, Regex::MatchData, Array(Int32)),
      Type::ZeroArgStatement => ->mapperStatement(Program, Type, Regex::MatchData, Array(Int32)),
      Type::OneArgStatement  => ->mapperStatement(Program, Type, Regex::MatchData, Array(Int32)),
      Type::TwoArgStatement  => ->mapperStatement(Program, Type, Regex::MatchData, Array(Int32)),
      Type::Program          => ->mapperDefault(Program, Type, Regex::MatchData, Array(Int32)),
    }

    class Error < Exception
    end

    # matcher is the matcher selection
    # src is the string to tokenize
    def self.tokenize(p : Program, src : String)
      tokens = Array(Node).new
      index = 0
      if p.pc.pass > 0
        matcher = 1
      else
        matcher = 0
      end
      while index < src.size
        m_off = 0
        matches = @@matchers[matcher].compact_map do |r, t|
          m = r.match(src[(index..)])
          if m.nil?
            next
          end
          {"m": m, "type": t}
        end
        if matches.size == 0
          # TODO: Perhaps the right way is to pass one on at a time and then fail when there are no longer any reductions?
          raise Error.new("Unexpected token #{src[index..index + 1]} @ #{index}")
        end
        if !matches[0].nil? && !matches[0][:m][0].nil?
          mapper = @@mappers[matches[0][:type]]
          if !mapper.nil?
            c = mapper.not_nil!
            m_off = matches[0][:m].begin(0)
            t = c.call(p, matches[0][:type], matches[0][:m], [index + m_off])
            if !t.nil?
              tokens.concat(t)
            end
          end
          index += m_off + matches[0][:m][0].size
          p.pc.inc
        else
          raise Error.new("Unexpected match in token array #{src[index..index + 1]}")
        end
      end
      tokens
    end

    def tokens_to_s(tokens)
      tokens.map { |token| token.type.value.chr }.join
    end

    def self.tokens_to_s(tokens)
      tokens.map { |token| token.type.value.chr }.join
    end

    # TODO: Implement to_json
    def to_json
    end
  end
end
