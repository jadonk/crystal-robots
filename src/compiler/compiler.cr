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

    PassToken = 0x00000156 # œ

    Statement        = 0x00002762 # ❢
    ZeroArgStatement = 0x00002763 # ❣
    OneArgStatement  = 0x00002764 # ❤
    TwoArgStatement  = 0x00002765 # ❥
    Program          = 0x000023F9 # ⏹
  end

  # A `Program` is the result of parsing the source file and used for generating code or interpreting.
  #
  # A `Program` should look like string, but some of the characters will point to another
  # a subset of characters that provide more detail about what they represent. When the source has been fully
  # parsed, the final character will point to a sequence of statements.
  #
  # To speed up implementation, I'll start with just making new strings, but, eventually, I'll do some
  # smart allocation and fill in the empty space.
  #
  # `source` holds the string of the source program along with the generated tokens.
  # `ast` is an array of Node associated to each generated token pointing to regions in the string.
  # `pc` is the index to the current token when adding or interpreting. -1 is unintialized.
  # `stack` is an array of indexes used for returning from calls.
  # `walkmode` is the mode used for enumeration and .to_s String conversion operation.
  # `pass` is an array of indexes for the first token for each pass of tokenization.
  class Program
    property source, ast, pc, stack, walkmode, pass

    # A `Node` is meant to be kept in an array. It is synonomous with a token.
    # Each `Node` has a token `type` to reflect what was found.
    # The `start` is the origin offset in source string, including generated tokens.
    # The `count` is the length of the string matched.
    # The `nxt` is the origin offset in the array to the next token such that tokens that
    # have been combined can be skipped. If it isn't initialized, it is set to -1 and that
    # simply means that the next token is just the next one in the array.
    struct Node
      property type, start, count, nxt

      def initialize(@type : Type, @start : Int32 = -1, @count : Int32 = 0, @nxt : Int32 = -1)
      end

      def to_s(io : IO)
        io << "'#{@type.value.chr}' from #{@start} length #{@count} next @#{@nxt}"
      end
    end

    include Enumerable(Node)

    enum WalkMode
      Follow
      Linear
      Top
    end

    def push(type : Type, start : Int32 = -1, count : Int32 = -1, nxt : Int32 = -1)
      node = Node.new(type, start, count, nxt)
      @ast.push(node)
    end

    def initialize(@source : String,
                   @ast : Array(Node) = [] of Node,
                   @pc : Int32 = -1,
                   @stack : Array(Int32) = [] of Int32,
                   @walkmode : WalkMode = WalkMode::Follow,
                   @pass : Array(Int32) = [] of Int32)
      src = @source + "#{Type::PassToken.value.chr}"
      push(Type::PassToken, 0, src.size)
      @pass.push(src.size)
      @source = src
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
          if node.nxt > 0
            @pc = node.nxt
          else
            inc
          end
        when WalkMode::Linear
          inc
        end
        if !test_pc
          break
        end
      end
    end

    def [](i : Int32)
      @ast[i]
    end

    def [](start : Int32, count : Int32)
      src = @source.not_nil!
      src[start, count]
    end

    def node
      node(@pc)
    end

    def node(pc : Int32)
      x = @ast[pc].not_nil!
      Log.d "node @#{pc}: #{x}"
      x
    end

    # Return the value pointed to by the node
    def value(n : Node)
      @source[n.start, n.count]
    end

    def value(i : Int32)
      value(node(i))
    end

    def value
      value(node)
    end

    def type(i : Int32)
      node(i).type
    end

    def start(i : Int32)
      node(i).start
    end

    def count(i : Int32)
      node(i).count
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
      i = m.start
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
      io << "#{s} pc: #{@pc} pass: #{@pass} stack: #{@stack}"
    end
  end

  # TODO: decide how we want to call the compiler and remove this method
  def self.compile_to_wasm(source : String)
    Bytes[]
  end

  # TODO: decide how we want to call the interpreter and remove this method
  def self.interpret(source : String)
    Bytes[]
  end
end
