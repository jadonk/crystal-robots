# TODO: Write documentation for `CrystalRobots::Compiler::Tokenizer`

module CrystalRobots::Compiler
  class Tokenizer
    @source : String
    @tokens : Array(Token)
    @ast : Program

    def initialize(string : String)
      @source = string
      #@tokens = tokenize(string)
      #@ast = Program.new([@tokens])
    end

    def tokens
      @tokens
    end

    struct Token
      property type, value, index

      def initialize(@type : Type, @value : String, @index : Array(Int32))
      end
    end

    enum Type : Int32
      String           = 0x0001F40D # 🐍
      Number           = 0x00002116 # №
      Keyword          = 0x0001F511 # 🔑 <--
      BeginKeyword     = 0x0001F512 # 🔒
      BreakKeyword     = 0x0001F513 # 🔓
      CaseKeyword      = 0x0001F514 # 🔔
      DefKeyword       = 0x0001F515 # 🔕
      DoKeyword        = 0x0001F516 # 🔖
      ElseKeyword      = 0x0001F517 # 🔗
      ElsifKeyword     = 0x0001F518 # 🔘
      EndKeyword       = 0x0001F519 # 🔙
      FalseKeyword     = 0x0001F51A # 🔚
      ForKeyword       = 0x0001F51B # 🔛
      IfKeyword        = 0x0001F51C # 🔜
      InKeyword        = 0x0001F51D # 🔝
      NextKeyword      = 0x0001F51E # 🔞
      NilKeyword       = 0x0001F51F # 🔟
      RequireKeyword   = 0x0001F520 # 🔠
      ThenKeyword      = 0x0001F521 # 🔡
      TrueKeyword      = 0x0001F522 # 🔢
      WhileKeyword     = 0x0001F523 # 🔣
      Builtin          = 0x00002208 # ∈ <--
      ZeroArgBuiltin   = 0x00002209 # ∉
      OneArgBuiltin    = 0x0000220A # ∊
      TwoArgBuiltin    = 0x0000220B # ∋
      Whitespace       = 0x00002422 # ␢
      Comment          = 0x0001F4AC # 💬
      OpenParen        = 0x000027EE # ⟮
      CloseParen       = 0x000027EF # ⟯
      Expression       = 0x0001F611 # 😑
      Statement        = 0x00002762 # ❢ <--
      ZeroArgStatement = 0x00002763 # ❣
      OneArgStatement  = 0x00002764 # ❤
      TwoArgStatement  = 0x00002765 # ❥
      Program          = 0x000023F9 # ⏹
    end

    # These are language keywords that generate various statement types
    @@keywords = [
      "begin",
      "break",
      "case",
      "def",
      "do",
      "else",
      "elsif",
      "end",
      "false",
      "for",
      "if",
      "in",
      "next",
      "nil",
      "require",
      "then",
      "true",
      "while",
    ]
    @@keywords_s : String
    @@keywords_s = @@keywords.join("|")
    @@keywords_h = Hash(String, Int32).new(0)
    @@keywords.each_index do |i|
      @@keywords_h[@@keywords[i]] = i + 1
    end

    # These are methods already defined
    @@builtins = [
      {"main", 2},
      {"puts", 1},
      {"scan", 2},
      {"cannon", 2},
      {"drive", 2},
      {"damage", 0},
      {"speed", 0},
      {"loc_x", 0},
      {"loc_y", 0},
      {"rand", 1},
      {"sqrt", 1},
      {"sin", 1},
      {"cos", 1},
      {"tan", 1},
      {"atan", 1},
    ]
    @@builtins_s : String
    @@builtins_s = (@@builtins.map { |s, n| s }).join("|")
    @@builtins_h = Hash(String, Int32).new(0)
    @@builtins.each_index do |i|
      @@builtins_h[@@builtins[i][0]] = @@builtins[i][1]
    end

    @@statements : Array(Type)
    @@statements = [
      Type::ZeroArgStatement,
      Type::OneArgStatement,
      Type::TwoArgStatement,
    ]
    @@statements_s : String
    @@statements_s = (@@statements.map { |t| t.value.chr }).join("|")

    @@a = 0
    @@matchers = [
      [
        {/^\"([^\"]+)\"/, Type::String},
        {/^(-{0,1}[\.0-9]+)/, Type::Number},
        {Regex.new("^(#{@@keywords_s})"), Type::Keyword},
        {Regex.new("^(#{@@builtins_s})"), Type::Builtin},
        {/^(\s+)/, Type::Whitespace},
        {/^\#.*$/, Type::Comment},
        {/^(\()/, Type::OpenParen},
        {/^(\))/, Type::CloseParen},
      ],
      [
        {/^(∉)/, Type::ZeroArgStatement},
        {/^(∊(№|🐍))/, Type::OneArgStatement},
        {/^(∋(№|🐍)(№|🐍))/, Type::TwoArgStatement},
        {Regex.new("^(#{@@statements_s})+"), Type::Program},
      ],
    ]

    def self.mapperDefault(t : Type, m : Regex::MatchData, i : Array(Int32))
      value = m[0]
      if t == Type::Keyword
        t += @@keywords_h[value]
      elsif t == Type::Builtin
        t += @@builtins_h[value] + 1
      end
      puts "#{t} #{value} #{i}"
      Token.new(type: t, value: value, index: i)
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
      puts "#{t} #{value} #{a}"
      Token.new(type: t, value: value, index: a)
    end

    @@mappers : Hash(Type, Proc(Type, Regex::MatchData, Array(Int32), Token) | Nil)
    @@mappers = {
      Type::String           => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Number           => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Keyword          => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Builtin          => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Whitespace       => nil,
      Type::Comment          => nil,
      Type::ZeroArgStatement => ->mapperStatement(Type, Regex::MatchData, Array(Int32)),
      Type::OneArgStatement  => ->mapperStatement(Type, Regex::MatchData, Array(Int32)),
      Type::TwoArgStatement  => ->mapperStatement(Type, Regex::MatchData, Array(Int32)),
      Type::Program          => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
    }

    class Error < Exception
    end

    def tokenize(src : String)
      tokens = Array(Token).new
      index = 0
      while index < src.size
        matches = @@matchers[@@a].compact_map do |r, t|
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
              tokens << t
            end
          end
          index += matches[0][:m][0].size
        else
          raise Error.new("Unexpected match in token array #{src[index..index + 1]}")
        end
      end
      tokens
    end

    def parse
      @@a = 0
      src = @source
      while true
        puts "tokenize(#{src})"
        @tokens = tokenize(src)
        @ast << @tokens
        src = to_s
        if src == "⏹"
          puts src
          break
        end
        @@a = 1
      end
      @ast
    end

    def to_s
      @tokens.map { |token| token.type.value.chr }.join
    end

    def to_array_s
      @ast.ast.map do |a|
        a.map { |token| token.type.value.chr }.join
      end
    end

    # TODO: Implement to_json
    def to_json
    end
  end
end
