# TODO: Write documentation for `CrystalRobots::Compiler::Tokenizer`

module CrystalRobots::Compiler
  class Tokenizer
    @source : String
    @tokens : Array(Token)
    @ast : Array(Array(Token))

    def initialize(string : String)
      @source = string
      @tokens = tokenize(string)
      @ast = [@tokens]
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
      String         = 0x0001F40D # 🐍
      Number         = 0x00002116 # №
      Keyword        = 0x0001F511 # 🔑
      BeginKeyword   = 0x0001F512 # 🔒
      BreakKeyword   = 0x0001F513 # 🔓
      CaseKeyword    = 0x0001F514 # 🔔
      DefKeyword     = 0x0001F515 # 🔕
      DoKeyword      = 0x0001F516 # 🔖
      ElseKeyword    = 0x0001F517 # 🔗
      ElsifKeyword   = 0x0001F518 # 🔘
      EndKeyword     = 0x0001F519 # 🔙
      FalseKeyword   = 0x0001F51A # 🔚
      ForKeyword     = 0x0001F51B # 🔛
      IfKeyword      = 0x0001F51C # 🔜
      InKeyword      = 0x0001F51D # 🔝
      NextKeyword    = 0x0001F51E # 🔞
      NilKeyword     = 0x0001F51F # 🔟
      RequireKeyword = 0x0001F520 # 🔠
      ThenKeyword    = 0x0001F521 # 🔡
      TrueKeyword    = 0x0001F522 # 🔢
      WhileKeyword   = 0x0001F523 # 🔣
      Builtin        = 0x00002208 # ∈
      Whitespace     = 0x00002422 # ␢
      Comment        = 0x0001F4AC # 💬
      OpenParen      = 0x000027EE # ⟮
      CloseParen     = 0x000027EF # ⟯
      Expression     = 0x0001F611 # 😑
      Statement      = 0x00002762 # ❢
      Program        = 0x000023F9 # ⏹
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
    ].join("|")

    # These are classes/methods already defined
    @@builtins = [
      "main",
      "puts",
      "scan",
      "cannon",
      "drive",
      "damage",
      "speed",
      "loc_x",
      "loc_y",
      "rand",
      "sqrt",
      "sin",
      "cos",
      "tan",
      "atan",
    ].join("|")

    @@a = 0
    @@matchers = [
      [
        {/^\"([^\"]+)\"/, Type::String},
        {/^([.0-9]+)/, Type::Number},
        {Regex.new("^(#{@@keywords})"), Type::Keyword},
        {Regex.new("^(#{@@builtins})"), Type::Builtin},
        {/^(\s+)/, Type::Whitespace},
        {/^\#.*$/, Type::Comment},
        {/^(\()/, Type::OpenParen},
        {/^(\))/, Type::CloseParen},
      ],
      [
        {/^(∈🐍)/, Type::Statement},
        {/^(❢+)$/, Type::Program},
      ],
    ]

    def self.mapperDefault(t : Type, m : Regex::MatchData, i : Array(Int32))
      t = Token.new(type: t, value: m[0], index: i)
    end

    @@mappers : Hash(Type, Proc(Type, Regex::MatchData, Array(Int32), Token) | Nil)
    @@mappers = {
      Type::String     => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Number     => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Keyword    => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Builtin    => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Whitespace => nil,
      Type::Comment    => nil,
      Type::Statement  => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
      Type::Program    => ->mapperDefault(Type, Regex::MatchData, Array(Int32)),
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
          raise Error.new("Unexpected token #{src[index..index + 1]}")
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
      @@a = 1
      while true
        # puts to_s
        @tokens = tokenize(to_s)
        @ast << @tokens
        if to_s == "⏹"
          # puts to_s
          break
        end
      end
      @ast
    end

    def to_s
      @tokens.map { |token| token.type.value.chr }.join
    end

    def to_array_s
      @ast.map do |a|
        a.map { |token| token.type.value.chr }.join
      end
    end

    # TODO: Implement to_json
    def to_json
    end
  end
end
