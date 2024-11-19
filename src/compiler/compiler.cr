# TODO: Write documentation for `CrystalRobots::Compiler`
# Crystal Robots compiler
#
# ## Description
#
# The Crystal Robots compiler accepts a limited subset of the [Crystal Programming Language](https://crystal-lang.org). The entire program must be a single source file. No macro operations are supported. The compile machine code targets [WebAssembly](https://webassembly.org/) and calls various functions in a browser-based simulation
#
# ## Features missing
require "./parser.cr"
require "./interpreter.cr"
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

  def self.interpret(src)
    p = Parser.new(src)
    Interpreter.execute(p.program)
  end

  enum Type : Int32
    String = 0x0001F40D # 🐍
    Number = 0x00002116 # №

    Operator         = 0x0000229A # ⊚
    AddOperator      = 0x00002295 # ⊕
    SubOperator      = 0x00002296 # ⊖
    MulOperator      = 0x00002297 # ⊗
    FloorDivOperator = 0x00002298 # ⊘
    EqOperator       = 0x0000225F # ≟
    NeOperator       = 0x00002260 # ≠
    GtOperator       = 0x0000227B # ≻
    LtOperator       = 0x0000227A # ≺
    AndOperator      = 0x00002227 # ∧
    OrOperator       = 0x00002228 # ∨
    XorOperator      = 0x000022BB # ⊻

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
    ZeroArgBuiltin = 0x00002209 # ∉
    OneArgBuiltin  = 0x0000220A # ∊
    TwoArgBuiltin  = 0x0000220B # ∋
    Whitespace     = 0x00002422 # ␢
    Comment        = 0x0001F4AC # 💬
    OpenParen      = 0x000027EE # ⟮
    CloseParen     = 0x000027EF # ⟯
    Expression     = 0x0001F611 # 😑

    Statement        = 0x00002762 # ❢
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

  struct PC
    property pass, index

    def initialize(@pass : Int32, @index : Int32)
    end

    def inc
      @index += 1
      self
    end

    def inc(i : Int32)
      @index += i
      self
    end
    
    def to_s
      "@(#{@pass},#{@index})"
    end
  end

  struct Program
    property ast, pc, call_stack

    def initialize
      @ast = [] of Array(Node)
      @pc = PC.new(0, 0)
      @call_stack = [] of Int32
    end

    def initialize(@ast : Array(Array(Node)), @pc : PC, @call_stack : Array(Int32))
    end

    def <<(token : Node)
      @index += 1
      @ast[@pc.pass] << token
    end

    def <<(tokens : Array(Node))
      @index += tokens.size
      @ast[@pc.@pass].concat(tokens)
    end

    def add_pass(tokens : Array(Node))
      @ast << tokens
      @pc.index = 0
      @pc.pass += 1
    end

    def [](i)
      @ast[i]
    end

    def map(& : Array(Node) -> String) : Array(String)
      Array(String).new(@ast.size) { |i| yield @ast[i] }
    end

    def node
      Log.d "Fetching node #{@pc}"
      @ast[@pc.pass][@pc.index]
    end

    def node(pc : PC)
      Log.d "Fetching node #{pc}"
      @ast[pc.pass][pc.index]
    end

    def size
      @ast.size
    end

    def inc
      @pc.inc
    end

    def inc(i : Int32)
      @pc.inc(i)
    end

    def start
      if @ast.size < 3
        raise "not enough passes running tokenize"
      end
      @pc.pass = @ast.size - 2
      @pc.index = 0
    end

    def next_pass
      @pc.pass += 1
      @pc.index = 0
    end

    def jump(pc : PC)
      @pc = pc
    end

    # We know for every call, pass is reduced by 1
    def call(i : Int32)
      if pc.pass <= 1
        raise "Call pass maximum depth"
      end
      @call_stack << @pc.index
      @pc.pass -= 1
      @pc.index = i
    end

    def return
      @pc.pass += 1
      @pc.index = @call_stack.pop
    end

    def test_pc(pc : PC)
      pc.pass >= 0 && pc.index >= 0 && pc.pass < @ast.size && pc.index < @ast[pc.pass].size
    end

    def arg(pc : PC, n : Int32)
      if pc.pass <= 0
        raise "I need to add handling of indexes into the source string"
      end
      if n >= node.index.size
        raise "Not enough arguments"
      end
      @ast[pc.pass - 1][node.index[n]]
    end

    # Program#arg(0) should return the first Node pointed to by the current Node
    def arg(n : Int32)
      arg(@pc, n)
    end

    def tokens_to_s(tokens)
      tokens.map { |token| token.type.value.chr }.join
    end

    def to_s
      s = @ast.map { |a| tokens_to_s(a) }.join('\n')
      t = s
      "#{t}\n @ #{@pc.pass},#{@pc.index}"
    end
  end
end
