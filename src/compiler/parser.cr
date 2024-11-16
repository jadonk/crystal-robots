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
      @ast = Program.new
    end

    def self.new(src : String)
      a = 0
      ast = Program.new
      while src != "⏹" && src != ""
        puts "tokenize(#{a}, #{src})"
        nodes = tokenize(a, src)
        ast << nodes
        src = tokens_to_s(nodes)
        a = 1
      end
      i = Parser.allocate
      i.initialize(src)
      i.program = ast
      i
    end

    def program
      @ast
    end

    protected def program=(@ast : Program)
    end

    # These are language keywords that generate various statement types
    @@keywords = [
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
    ]
    @@keywords_s : String
    @@keywords_s = (@@keywords.map { |s, n| s }).join("|")
    @@keywords_h = Hash(String, Type).new
    @@keywords.each_index do |i|
      @@keywords_h[@@keywords[i][0]] = @@keywords[i][1]
    end

    # Builtins are methods already defined that can be combined with
    # optional arguments to make a statement
    @@builtins = [
      {"main", Type::TwoArgBuiltin},
      {"puts", Type::OneArgBuiltin},
      {"scan", Type::TwoArgBuiltin},
      {"cannon", Type::TwoArgBuiltin},
      {"drive", Type::TwoArgBuiltin},
      {"damage", Type::ZeroArgBuiltin},
      {"speed", Type::ZeroArgBuiltin},
      {"loc_x", Type::ZeroArgBuiltin},
      {"loc_y", Type::ZeroArgBuiltin},
      {"rand", Type::OneArgBuiltin},
      {"sqrt", Type::OneArgBuiltin},
      {"sin", Type::OneArgBuiltin},
      {"cos", Type::OneArgBuiltin},
      {"tan", Type::OneArgBuiltin},
      {"atan", Type::OneArgBuiltin},
    ]
    @@builtins_s : String
    @@builtins_s = (@@builtins.map { |s, n| s }).join("|")
    @@builtins_h = Hash(String, Type).new
    @@builtins.each_index do |i|
      @@builtins_h[@@builtins[i][0]] = @@builtins[i][1]
    end

    # Operators used to make expressions
    @@operators = [
      {"+", Type::AddOperator},
      {"-", Type::SubOperator},
      {"*", Type::MulOperator},
      {"//", Type::FloorDivOperator},
      {"==", Type::EqOperator},
      {"!=", Type::NeOperator},
      {">", Type::GtOperator},
      {"<", Type::LtOperator},
      {"&", Type::AndOperator},
      {"|", Type::OrOperator},
      {"^", Type::XorOperator},
    ]
    @@operators_s : String
    @@operators_s = (@@operators.map { |s, n| Regex.escape(s) }).join("|")
    @@operators_h = Hash(String, Type).new
    @@operators.each_index do |i|
      @@operators_h[@@operators[i][0]] = @@operators[i][1]
    end

    # Statements are the top-level building blocks of a program
    @@statements : Array(Type)
    @@statements = [
      Type::ZeroArgStatement,
      Type::OneArgStatement,
      Type::TwoArgStatement,
    ]
    @@statements_s : String
    @@statements_s = (@@statements.map { |t| t.value.chr }).join("|")

    @@matchers = [
      [
        {/^\"([^\"]+)\"/, Type::String},
        {/^(-{0,1}[\.0-9]+)/, Type::Number},
        {Regex.new("^(#{@@keywords_s})"), Type::Keyword},
        {Regex.new("^(#{@@builtins_s})"), Type::Builtin},
        {Regex.new("^(#{@@operators_s})"), Type::Operator},
        {/^(\s+)/, Type::Whitespace},
        {/^\#.*$/, Type::Comment},
        {/^(\()/, Type::OpenParen},
        {/^(\))/, Type::CloseParen},
      ],
      [
        {/(№⊚№)/, Type::Expression},
        {/^(∉)/, Type::ZeroArgStatement},
        {/^(∊(№|🐍|😑))/, Type::OneArgStatement},
        {/^(∋(№|🐍|😑)(№|🐍|😑))/, Type::TwoArgStatement},
        {Regex.new("^(#{@@statements_s})+"), Type::Program},
      ],
    ]

    def self.mapperDefault(t : Type, m : Regex::MatchData, i : Array(Int32))
      value = m[0]
      if t == Type::Keyword
        t = @@keywords_h[value]
      elsif t == Type::Builtin
        t = @@builtins_h[value]
      end
      puts "default: #{t} #{value} #{i}"
      [ Node.new(type: t, value: value, index: i) ]
    end

    def self.mapperStatement(t : Type, m : Regex::MatchData, i : Array(Int32))
      value = m[0]
      case t
      when Type::OneArgStatement
        a = [i[0], i[0] + 1]
      when Type::TwoArgStatement
        a = [i[0], i[0] + 1, i[0] + 2]
      else
        a = [i[0]]
      end
      puts "statment: #{t} #{value} #{a}"
      [ Node.new(type: t, value: value, index: a) ]
    end

    def self.mapperExpression(t : Type, m : Regex::MatchData, i : Array(Int32))
      n = i[0]
      a = [n+1, n, n+2]
      value = m[0]
      puts "expression: #{t} #{value} #{i} @ #{m.begin(0)}"
      tokens = Array(Node).new
      m.begin(0).times do |j|
        puts "need to push #{m.string[j]}"
        n_off = n - m.begin(0) + j
        tokens << Node.new(type: Type.new(m.string[j].ord), value: "passthrough", index: [n_off])
      end
      tokens << Node.new(type: t, value: value, index: a)
    end

    @@mappers : Hash(Type, Proc(Type, Regex::MatchData, Array(Int32), Array(Node)) | Nil)
    @@mappers = {
      Type::String           => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Number           => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Keyword          => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Builtin          => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Operator         => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Whitespace       => nil,
      Type::Comment          => nil,
      Type::Expression       => ->mapperExpression(Type, Regex::MatchData, Array(Int32)),
      Type::ZeroArgStatement => ->mapperStatement(Type, Regex::MatchData, Array(Int32)),
      Type::OneArgStatement  => ->mapperStatement(Type, Regex::MatchData, Array(Int32)),
      Type::TwoArgStatement  => ->mapperStatement(Type, Regex::MatchData, Array(Int32)),
      Type::Program          => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
    }

    class Error < Exception
    end

    # matcher is the matcher selection
    # src is the string to tokenize
    def self.tokenize(matcher : Number, src : String)
      tokens = Array(Node).new
      index = 0
      while index < src.size
        matches = @@matchers[matcher].compact_map do |r, t|
          m = r.match(src[(index..)])
          if m.nil?
            next
          end
          {"m": m, "type": t}
        end
        if matches.size == 0
          raise Error.new("Unexpected token #{src[index..index + 1]} @ #{index}")
        end
        if !matches[0].nil? && !matches[0][:m][0].nil?
          mapper = @@mappers[matches[0][:type]]
          if !mapper.nil?
            c = mapper.not_nil!
            t = c.call(matches[0][:type], matches[0][:m], [index])
            if !t.nil?
              tokens.concat(t)
            end
          end
          index += matches[0][:m].begin(0) + matches[0][:m][0].size
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

    def to_s
      @ast.map { |a| tokens_to_s(a) }.join('\n')
    end

    # TODO: Implement to_json
    def to_json
    end
  end
end
