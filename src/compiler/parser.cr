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
      Drop
      Expression
      Program
    end

    # 1. Start by matching the first Regex. If initially assigned Nil in creation, it should get 
    #    assigned by the next argument (TokenDef).
    # 2. Next, use the TokenDef Hash to select a type. If the rule Regex is Nil, assign it using the
    #    TokenDef Regex. If the it TokenDef Hash doesn't have a value match, don't assign a type yet.
    # 3. Next, use the provided type to set a type. If it is Nil, keep the already assigned type. If that is Nil, error out.
    # 4. Finally, run the mapping function using the mapping type to set the final node parameters. If it is Nil, drop the token.
    struct GrammarRule
      property rule

      def initialize(@rule : Tuple(Regex, TokenDef | Nil, Type | Nil, MappingType | Nil))
      end

      def initialize(rs : Tuple(Regex | Nil, Array(Tuple(String, Type)) | Nil, Type | Nil, MappingType | Nil))
        regex = rs[0]
        tokendef = TokenDef.new(rs[1])
        if regex.nil?
          regex = tokendef.r.not_nil!
        end
        @rule = {rs[0], tokendef, rs[2], rs[3]}
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
          i.grammar.push(GrammerRule.new(r[0], r[1], r[2], r[3]))
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
                    {"*", Type::Operator},
                    {"//", Type::Operator},
                  ], Type::Operator, MappingType::Default},
    {nil,
                  [
                    {"+", Type::Operator},
                    {"-", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    },
    {nil,
                  [
                    {"==", Type::Operator},
                    {"!=", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    },
    {nil,
                  [
                    {"<", Type::Operator},
                    {">", Type::Operator},
                    {"<=", Type::Operator},
                    {">=", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    },
    {nil,
                  [
                    {"&", Type::Operator},
                  ], Type::Operator, MappingType::Default,
    },
    {nil,
                  [
                    {"|", Type::Operator},
                    {"^", Type::Operator},
                  ], Type::Operator, MappingType::Default,
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
    {/^\#.*$/, nil, Type::Comment, nil},
    {/(№⊚№)/, nil, Type::Expression, MappingType::Default},
    {/^(∉)/, nil, Type::ZeroArgStatement, MappingType::Default},
    {/^(∊(№|🐍|😑))/, nil, Type::OneArgStatement, MappingType::Default},
    {/^(∋(№|🐍|😑)(№|🐍|😑))/, nil, Type::TwoArgStatement, MappingType::Default},
    {/^[❣❤❥]+$/, nil, Type::Program, MappingType::Program},
        
      ]
    )

    def self.map(p : Program, t : Type, m : Regex::MatchData, i : Array(Int32), td : TokenDef | Nil, mt: MappingType)
      # i is an array right now, but I don't think it needs to be as we know the length
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
      Log.d "map: #{t} #{value} #{i}"
      tokens << Node.new(type: t, value: value, index: a)
    end

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
