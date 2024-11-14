# TODO: Write documentation for `CrystalRobots::Compiler`
# Crystal Robots compiler
#
# ## Description
#
# The Crystal Robots compiler accepts a limited subset of the [Crystal Programming Language](https://crystal-lang.org). The entire program must be a single source file. No macro operations are supported. The compile machine code targets [WebAssembly](https://webassembly.org/) and calls various functions in a browser-based simulation
#
# ## Features missing
require "./parser.cr"
require "./wasm_emitter.cr"

module CrystalRobots::Compiler
  def self.parse(src)
    # puts "Parsing #{src}"
    Parser.new(src)
  end

  def self.compile_to_wasm(src)
    # puts "Parsing #{src}"
    p = Parser.new(src)
    # puts "Emitting WASM from #{p}"
    WASM_Emitter.new(p.program).to_wasm
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

  struct Node
    property type, value, index

    def initialize(@type : Type, @value : String, @index : Array(Int32))
    end
  end

  struct Program
    property ast

    def initialize
      @ast = [] of Array(Node)
    end

    def initialize(@ast : Array(Array(Node)))
    end

    def <<(tokens : Array(Node))
      @ast << tokens
    end

    def [](i)
      @ast[i]
    end

    def map(& : Array(Node) -> String) : Array(String)
      Array(String).new(@ast.size) { |i| yield @ast[i] }
    end
  end
end
