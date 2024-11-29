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

    struct TokenDef
      property v, s, h, r

      def initialize(@v : Array(Tuple(String, Type)) | Nil, @s : String, @h : Hash(String, Type), @r : Regex | Nil)
      end

      def initialize(values : Array(Tuple(String, Type)))
        @v = values
        @h = Hash(String, Type).new(default_value = Type::Invalid, initial_capacity = 20)
        if !@v.nil?
          v = @v.not_nil!
          @s = (v.map { |s, t| Regex.escape(s) }).join("|")
          @r = Regex.new("^(#{@s})")
          v.each_index do |i|
            @h[v[i][0]] = v[i][1]
          end
        else
          @s = ""
          @r = nil
        end
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
        @h = Hash(String, Type).new(default_value = Type::Invalid, initial_capacity = 20)
        @r = nil
      end
    end

    enum MappingType
      Default
      Drop
      Program
      Parenthetical
    end

    # 1. Start by matching the first Regex. If initially assigned Nil in creation, it should get
    #    assigned by the next argument (TokenDef).
    # 2. Next, use the TokenDef Hash to select a type. If the rule Regex is Nil, assign it using the
    #    TokenDef Regex. If the it TokenDef Hash doesn't have a value match, don't assign a type yet.
    # 3. Next, use the provided type to set a type. If it is Nil, keep the already assigned type. If that is Nil, error out.
    # 4. Finally, run the mapping function using the mapping type to set the final node parameters. If it is Nil, drop the token.
    struct GrammarRule
      property regex, tokendef, type, map

      def initialize(@regex : Regex, @tokendef : TokenDef, @type : Type | Nil, @map : MappingType)
      end

      def initialize(rs : Tuple(Regex | Nil, Array(Tuple(String, Type)) | Nil, Type | Nil, MappingType | Nil))
        regex = rs[0]
        tokendef = TokenDef.new(rs[1])
        if regex.nil?
          regex = tokendef.r.not_nil!
        end
        map = rs[3]
        if map.nil?
          map = MappingType::Drop
        end
        @regex = regex
        @tokendef = tokendef
        @type = rs[2]
        @map = map
      end
    end

    def self.tokenize(p : Program, src : String)
      tokens = Array(Node).new
      tokens
    end

    struct Grammar
      property grammar

      def initialize(@grammar : Array(GrammarRule))
      end

      def self.new(rs : Array(Tuple(Regex | Nil, Array(Tuple(String, Type)) | Nil, Type | Nil, MappingType | Nil)))
        i = Grammar.allocate
        i.grammar = Array(GrammarRule).new
        rs.each do |r|
          i.grammar.push(GrammarRule.new({r[0], r[1], r[2], r[3]}))
        end
        i
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
    @@grammar = CrystalRobots::Compiler::Parser::Grammar.new(
      [
        {/^\"([^\"]+)\"/, nil, Type::String, MappingType::Default},
        {/^(-{0,1}[\.0-9]+)/, nil, Type::Number, MappingType::Default},
        {/^(\(|\))/,
         [
           {"(", Type::OpenParen},
           {")", Type::CloseParen},
         ],
         nil, MappingType::Default},
        {nil,
         [
           {"*", Type::MulOperator},
           {"//", Type::FloorDivOperator},
         ], Type::MulOperator, MappingType::Default},
        {nil,
         [
           {"+", Type::AddOperator},
           {"-", Type::SubOperator},
         ], Type::AddOperator, MappingType::Default,
        },
        {nil,
         [
           {"==", Type::EqOperator},
           {"!=", Type::NeOperator},
         ], Type::EqOperator, MappingType::Default,
        },
        {nil,
         [
           {"<", Type::LtOperator},
           {">", Type::GtOperator},
           {"<=", Type::LtOperator},
           {">=", Type::GtOperator},
         ], Type::LtOperator, MappingType::Default,
        },
        {nil,
         [
           {"&", Type::AndOperator},
         ], Type::AndOperator, MappingType::Default,
        },
        {nil,
         [
           {"|", Type::OrOperator},
           {"^", Type::XorOperator},
         ], Type::OrOperator, MappingType::Default,
        },
        {/^([a-z]+)\b/,
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
        },
        {/^(\s+)/, nil, Type::Whitespace, nil},
        {/^(\#[^\n]*)/, nil, Type::Comment, nil},
        # TODO: This makes me realize I need to have both a source type and a result type
        {/(⟮(№|😑)(⊗|⊕|≟|≺|∧|∨)(№|😑)⟯)/, nil, Type::Expression, MappingType::Parenthetical},
        {/((№|😑)⊗(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/((№|😑)⊕(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/((№|😑)≟(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/((№|😑)≟(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/((№|😑)≺(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/((№|😑)∧(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/((№|😑)∨(№|😑))/, nil, Type::Expression, MappingType::Default},
        {/^(∉)/, nil, Type::ZeroArgStatement, MappingType::Default},
        {/^(∊(№|🐍|😑))/, nil, Type::OneArgStatement, MappingType::Default},
        {/^(∋(№|🐍|😑)(№|🐍|😑))/, nil, Type::TwoArgStatement, MappingType::Default},
        {/^[❣❤❥]+$/, nil, Type::Program, MappingType::Program},
      ]
    )

    def self.map(p : Program, index : Int32, m : Regex::MatchData, rule : GrammarRule)
      value = m[0]
      case rule.map
      when MappingType::Drop
        nil
      when MappingType::Program
        if index != 0
          nil
        else
          type = rule.type.not_nil!
          [Node.new(type: type, value: value, index: 0)]
        end
      when MappingType::Default
        tokens = Array(Node).new
        m.begin(0).times do |j|
          i = index + j
          pc = PC.new(p.pc.pass - 1, i)
          n = p.node(pc).not_nil!
          t = Type.new(m.string[j].ord).not_nil!
          v = n.value.not_nil!
          Log.d "passing #{m.string[j]} as #{t} from #{v} #{pc}"
          tokens << Node.new(type: t, value: v, index: i)
        end
        t = rule.tokendef.h[value]
        if t == Type::Invalid
          if rule.type.nil?
            raise Error.new("Unexpected token #{value} @ #{index}")
          end
          t = rule.type.not_nil!
        end
        Log.d "mapping #{value} as #{t} using #{rule.map} @ #{index} offset by #{m.begin(0)}"
        tokens << Node.new(type: t, value: value, index: index + m.begin(0))
      when MappingType::Parenthetical
        # In this case, we want to drop the parentheses and point to the first
        # argument. The parentheses have done their job already by breaking up
        # things for the parser. At this point, everything inside the parentheses
        # has been resolved and we only have Value-Operator-Value. Even though
        # Value might be an expression, it is already isolated and prioritized.
        tokens = Array(Node).new
        m.begin(0).times do |j|
          i = index + j
          pc = PC.new(p.pc.pass - 1, i)
          node = p.node(pc)
          t = Type.new(m.string[j].ord).not_nil!
          n = node.not_nil!
          v = n.value.not_nil!
          Log.d "passing #{m.string[j]} as #{t} from #{v} #{pc}"
          tokens << Node.new(type: t, value: v, index: i)
        end
        t = rule.tokendef.h[value]
        if t == Type::Invalid
          if rule.type.nil?
            raise Error.new("Unexpected token #{value} @ #{index}")
          end
          t = rule.type.not_nil!
        end
        i = index + m.begin(0) + 1
        # value = value[1, value.size-2]
        Log.d "mapping #{value} as #{t} using #{rule.map} @ #{index} offset by #{m.begin(0) + 1}"
        tokens << Node.new(type: t, value: value, index: i)
      end
    end

    class Error < Exception
    end

    # src is the string to tokenize
    def self.tokenize(p : Program, src : String)
      tokens = Array(Node).new
      index = 0
      while index < src.size
        m_off = 0
        matches = @@grammar.grammar.compact_map do |rule|
          m = rule.regex.match(src[(index..)])
          if m.nil?
            next
          end
          {"m": m, "rule": rule}
        end
        if matches.size == 0
          # TODO: Perhaps the right way is to pass one on at a time and then fail when there are no longer any reductions?
          if index == 0
            raise Error.new("No tokens found in #{src}")
          end
          pc = PC.new(p.pc.pass - 1, index)
          node = p.node(pc).not_nil!
          t = node.type.not_nil!
          v = node.value.not_nil!
          Log.d "skipping #{src[index]} as #{t} from #{v} #{pc}"
          tokens << Node.new(type: t, value: v, index: index)
          index += 1
          p.pc.inc
        elsif !matches[0].nil? && !matches[0][:m][0].nil?
          m = matches[0][:m].not_nil!
          rule = matches[0][:rule].not_nil!
          t = self.map(p, index, m, rule)
          if !t.nil?
            tokens.concat(t)
          end
          index += m.begin(0) + m[0].size
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
