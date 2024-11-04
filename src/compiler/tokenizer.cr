# TODO: Write documentation for `CrystalRobots::Compiler::Tokenizer`

module CrystalRobots::Compiler
  class Tokenizer
    @tokens : Array(Token)

    def initialize(string : String)
      @tokens = tokenize(string)
    end

    def tokens
      @tokens
    end

    struct Token
      property type, value

      def initialize(@type : Type, @value : String)
      end
    end

    # ## Value
    #
    # * №    Number
    # * 🔑  Keyword
    # * ∈    Builtin
    # * 🐍  String
    # * ␢     Whitespace
    # * ⟮     OpenParen
    # * ⟯     CloseParen
    enum Type : Int32
      Number     = 0x00002116 # №
      Keyword    = 0x0001F511 # 🔑
      Builtin    = 0x00002208 # ∈
      String     = 0x0001F40D # 🐍
      Whitespace = 0x00002422 # ␢
      OpenParen  = 0x000027EE # ⟮
      CloseParen = 0x000027EF # ⟯
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

    @@matchers = [
      {/^\"([^\"]+)\"/, Type::String},
      {/^([.0-9]+)/, Type::Number},
      {Regex.new("^(#{@@keywords})"), Type::Keyword},
      {Regex.new("^(#{@@builtins})"), Type::Builtin},
      {/^(\s+)/, Type::Whitespace},
    ]

    class Error < Exception
    end

    def tokenize(src : String)
      tokens = Array(Token).new
      index = 0
      while index < src.size
        matches = @@matchers.compact_map do |regex, type|
          m = regex.match(src[(index..)])
          if m.nil?
            next
          end
          {"m": m, "type": type}
        end
        if matches.size == 0
          raise Error.new("Unexpected token #{src[index..index + 1]}")
        end
        if !matches[0].nil? && !matches[0][:m][0].nil?
          # puts "Found #{matches[0][:m][0]} as #{matches[0][:type]}"
          if matches[0][:type] != Type::Whitespace
            t = Token.new(type: matches[0][:type], value: matches[0][:m][0])
            tokens << t
          end
          index += matches[0][:m][0].size
        else
          raise Error.new("Unexpected match in token array #{src[index..index + 1]}")
        end
      end
      tokens
    end

    def to_s
      @tokens.map { |token| token.type.value.chr }.join
    end

    def to_json
      # TODO: Implement to_json
    end
  end
end
