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
    Invalid = 0x0001F30B # 🌋
    String  = 0x0001F40D # 🐍
    Number  = 0x00002116 # №

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

    Builtin       = 0x00002208 # ∈
    ZeroArgMethod = 0x00002209 # ∉
    OneArgMethod  = 0x0000220A # ∊
    TwoArgMethod  = 0x0000220B # ∋
    Whitespace    = 0x00002422 # ␢
    Comment       = 0x0001F4AC # 💬
    OpenParen     = 0x000027EE # ⟮
    CloseParen    = 0x000027EF # ⟯
    Expression    = 0x0001F611 # 😑

    Statement        = 0x00002762 # ❢
    ZeroArgStatement = 0x00002763 # ❣
    OneArgStatement  = 0x00002764 # ❤
    TwoArgStatement  = 0x00002765 # ❥
    Program          = 0x000023F9 # ⏹
  end

  # A `Node` is meant to be kept in an array. It can be said to be synonomous with a token.
  # Each `Node` has a token `type` to reflect what was found.
  # It also has a String `value`, which contains the original source content. This could be
  # replaced by a pointer into the original source string along with a length.
  # The `nxt` is the origin offset in the array to the next token such that tokens that
  # have been combined can be skipped. If it isn't initialized, it is set to -1 and that
  # simply means that the next token is just the next one in the array.
  # The `src` is the origin offset in source string or the array to the tokens this token
  # represents if greater than the size of the source string.
  struct Node
    property type, value, nxt, src

    def initialize(@type : Type, @value : String, @nxt : Int32 = -1, @src : Int32 = -1)
    end

    def to_s(io : IO)
      io << "'#{@type.value.chr}' \"#{@value}\" from #{@src} next @#{@nxt}"
    end
  end

  enum WalkMode
    Follow
    Linear
    Top
  end

  # A `Program` is the result of parsing the source file and used for generating code or interpreting.
  # `ast` is an array of nodes, also called tokens.
  # `pc` is the index to the current token when adding or interpreting. -1 is unintialized.
  # `stack` is an array of indexes used for returning from calls.
  # `walkmode` is the mode used for enumeration and .to_s String conversion operation.
  # `pass` is an array of indexes for the first token for each pass of tokenization.
  class Program
    include Enumerable(Node)
    property source, ast, pc, stack, walkmode, pass

    def initialize(@source : String | Nil = nil,
                   @ast : Array(Node) = [] of Node,
                   @pc : Int32 = -1,
                   @stack : Array(Int32) = [] of Int32,
                   @walkmode : WalkMode = WalkMode::Follow,
                   @pass : Array(Int32) = [] of Int32)
    end

    def each(&)
      if walkmode == WalkMode::Top
        pass = @pass[-1].not_nil!
        @pc = pass
      end
      while true
        yield self
        case walkmode
        when WalkMode::Follow | WalkMode::Top
          if n.nxt > 0
            @pc = n.nxt
          else
            inc
          end
        when WalkMode::Linear
          inc
        end
      end
      if !test_pc
        break
      end
    end

    def add_token(type : Type, value : String, src : Int32, len : Int32)
      s = src + pass_start
      token = Node.new(type: type, value: value, src: s)
      @ast.push(token)
    end

    def <<(token : Node)
      @pc += 1
      @ast.push(token)
    end

    def <<(tokens : Array(Node))
      @pc += tokens.size
      @ast.concat(tokens)
    end

    def add_pass(tokens : Array(Node))
      @ast.concat(tokens)
      @pc += tokens.size
      @ppc = @pc
    end

    def [](i)
      @ast[i]
    end

    def node
      x = @ast[@pc].not_nil!
      Log.d "node @#{@pc}: #{x}"
      x
    end

    def node(pc : Int32)
      x = @ast[pc].not_nil!
      Log.d "node @#{pc}: #{x}"
      x
    end

    def size
      @ast.size
    end

    def inc
      @pc += 1
    end

    def inc(i : Int32)
      @pc += i
    end

    def jump(pc : PC)
      @pc = pc
    end

    # We know for every call, pass is reduced by 1
    def call(i : Int32)
      @stack.push(@pc)
      @pc = i
    end

    def return
      @pc = @stack.pop
    end

    def test_pc(pc : Int32)
      pc >= 0 && pc < size
    end

    def test_pc
      test_pc(@pc)
    end

    def arg(pc : Int32, n : Int32)
      m = @ast[pc].not_nil!
      i = m.src
      arg_pc = i + n
      if !test_pc(arg_pc)
        raise "Invalid argument pointer #{arg_pc}"
      end
      node(arg_pc)
    end

    # Program#arg(0) should return the first Node pointed to by the current Node
    def arg(n : Int32)
      arg(@pc, n)
    end

    def to_s(io : IO)
      s = @ast.map { |token| token.type.value.chr }.join
      io << "#{s} pc: #{@pc} ppc: #{@ppc} stack: #{@stack}"
    end
  end
end
