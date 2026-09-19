# The multipass tokenizer's data model. See docs/PARSER.md for the design
# this grows into: every token kind is one reserved Unicode glyph, and
# parsing is a sequence of regex rewrites of the glyph string, one grammar
# rule per pass. `Type` and the rule table grow with each later commit;
# `Program` itself barely changes.
module CrystalRobots::Compiler
  # One glyph per token kind. The comment shows the glyph.
  enum Type : Int32
    Number        = 0x00002116 # №
    String        = 0x0001F40D # 🐍
    Identifier    = 0x0001D465 # 𝑥
    Newline       = 0x000023CE # ⏎  newline, end of input
    Comma         = 0x0000FF0C # ，
    ZeroArgMethod = 0x00002209 # ∉  damage speed loc_x loc_y sleep
    OneArgMethod  = 0x0000220A # ∊  puts rand sqrt sin cos tan atan
    TwoArgMethod  = 0x0000220B # ∋  scan cannon drive
    GlobalKeyword = 0x0001F310 # 🌐

    OpenParen  = 0x000027EE # ⟮
    CloseParen = 0x000027EF # ⟯
    Assign     = 0x0000FF1D # ＝
    AddAssign  = 0x00002795 # ➕
    SubAssign  = 0x00002796 # ➖
    MulAssign  = 0x00002716 # ✖
    ModAssign  = 0x00002052 # ⁒

    AddOperator      = 0x00002295 # ⊕
    SubOperator      = 0x00002296 # ⊖
    MulOperator      = 0x00002297 # ⊗
    DivOperator      = 0x0000FF0F # ／
    FloorDivOperator = 0x00002298 # ⊘
    ModOperator      = 0x0000FF05 # ％
    EqOperator       = 0x0000225F # ≟
    NeOperator       = 0x00002260 # ≠
    GtOperator       = 0x0000227B # ≻
    LtOperator       = 0x0000227A # ≺
    GeOperator       = 0x0000227D # ≽
    LeOperator       = 0x0000227C # ≼
    AndOperator      = 0x00002227 # ∧
    OrOperator       = 0x00002228 # ∨
    XorOperator      = 0x000022BB # ⊻

    WhileKeyword  = 0x0001F523 # 🔣
    UntilKeyword  = 0x0001F502 # 🔂
    EndKeyword    = 0x0001F519 # 🔙
    BreakKeyword  = 0x0001F513 # 🔓
    IfKeyword     = 0x0001F51C # 🔜
    ElsifKeyword  = 0x0001F518 # 🔘
    ElseKeyword   = 0x0001F517 # 🔗
    CaseKeyword   = 0x0001F514 # 🔔
    WhenKeyword   = 0x0001F536 # 🔶
    DefKeyword    = 0x0001F515 # 🔕
    ReturnKeyword = 0x000021A9 # ↩
    MainKeyword   = 0x0001F3C1 # 🏁
    DoKeyword     = 0x0001F516 # 🔖
    TrueKeyword   = 0x0001F522 # 🔢
    FalseKeyword  = 0x0001F51A # 🔚

    WhileHead = 0x0001F186 # 🆆
    UntilHead = 0x0001F184 # 🆄
    IfHead    = 0x0001F178 # 🅸
    ElsifHead = 0x0001F174 # 🅴
    DefHead   = 0x0001F173 # 🅳
    MainHead  = 0x0001F17C # 🅼
    CaseHead  = 0x0001F172 # 🅲
    WhenHead  = 0x0001F182 # 🆂

    Expression = 0x0001F611 # 😑  any reduced value
    Statement  = 0x00002762 # ❢
    Program    = 0x000023F9 # ⏹

    def glyph : Char
      value.chr
    end
  end

  # A `Program` is the source text plus every pass of the tokenizer, kept
  # as one string so the whole derivation can be printed. `pass[k]` is the
  # offset of pass k's glyph string inside `source`; `layers[k]` lists, for
  # each glyph position of pass k, the index of the `Node` that glyph
  # stands for.
  class Program
    # A `Node` is one glyph in one pass. Level 0 nodes come from the lexer
    # and `start`/`count` are character offsets into the source text. A
    # node made by pass k has level k and `start`/`count` cover the glyph
    # run it replaced in pass k-1, as absolute offsets into `source`. `rule`
    # names the grammar rule that produced the node (`:lex` for pass 0),
    # which is what emitters dispatch on.
    struct Node
      property type : Type, start : Int32, count : Int32, level : Int32, rule : Symbol

      def initialize(@type : Type, @start : Int32 = -1, @count : Int32 = 0, @level : Int32 = 0, @rule : Symbol = :lex)
      end
    end

    getter text : String
    getter ast = [] of Node
    getter pass = [] of Int32
    getter layers = [] of Array(Int32)
    getter rules = [] of Symbol

    def initialize(@text : String)
      @source = @text
    end

    getter source : String

    # Append a node and return its index.
    def push(type : Type, start : Int32 = -1, count : Int32 = 0, level : Int32 = 0, rule : Symbol = :lex) : Int32
      @ast << Node.new(type, start, count, level, rule)
      @ast.size - 1
    end

    # Record a finished pass: its glyph string goes onto `source`.
    def add_pass(layer : Array(Int32), rule : Symbol) : Nil
      @pass << @source.size
      @source += glyphs(layer)
      @layers << layer
      @rules << rule
    end

    def glyphs(layer : Array(Int32)) : String
      String.build { |io| layer.each { |i| io << @ast[i].type.glyph } }
    end

    # Total glyphs emitted by every pass so far: the parser's work so
    # far, distinct from the input's length -- a long operator chain
    # re-emits one fewer glyph each pass, so its cost is the square of
    # its length, not its length.
    def emitted : Int32
      @source.size - @text.size
    end

    # Node indexes of the latest pass.
    def current : Array(Int32)
      @layers.last? || [] of Int32
    end

    def passes : Int32
      @layers.size
    end

    def parsed? : Bool
      current.size == 1 && @ast[current[0]].type == Type::Program
    end

    def root : Int32
      raise "program is not parsed" unless parsed?
      current[0]
    end

    # One line per pass: the pass number, the rule, the glyph string.
    def derivation : String
      String.build do |io|
        @layers.each_with_index do |layer, k|
          io << k.to_s.rjust(3) << ' ' << @rules[k].to_s.ljust(11) << ' ' << glyphs(layer) << '\n'
        end
      end
    end

    def [](i : Int32) : Node
      @ast[i]
    end

    def type(i : Int32) : Type
      @ast[i].type
    end

    # The text a node covers: the lexeme for level 0, the replaced glyph
    # run for higher levels.
    def value(n : Node) : String
      @source[n.start, n.count]
    end

    def value(i : Int32) : String
      value(@ast[i])
    end

    # The lexeme of a level 0 node, or of the first level 0 node under it
    # (a node made by wrapping a single glyph in a rule like `call0`).
    def lexeme(i : Int32) : String
      n = @ast[i]
      return value(n) if n.level == 0
      lexeme(children(i)[0])
    end

    # Indexes of the nodes a reduction replaced, in order. Empty for level 0.
    def children(i : Int32) : Array(Int32)
      n = @ast[i]
      return [] of Int32 if n.level == 0
      layer = @layers[n.level - 1]
      pos = n.start - @pass[n.level - 1]
      layer[pos, n.count]
    end

    # The n-th child of node i.
    def arg(i : Int32, n : Int32) : Int32
      kids = children(i)
      raise "node #{i} has no child #{n}" unless n < kids.size
      kids[n]
    end

    # The source text offset where node i begins: its own, if it is a
    # level 0 node, otherwise its first child's, recursively.
    def origin(i : Int32) : Int32
      n = @ast[i]
      return n.start if n.level == 0
      kids = children(i)
      kids.empty? ? 0 : origin(kids[0])
    end

    # 1-based line and column of a text offset.
    def line_col(offset : Int32) : {Int32, Int32}
      before = @text[0, offset]
      {before.count('\n') + 1, offset - (before.rindex('\n') || -1)}
    end

    def location(i : Int32) : {Int32, Int32}
      line_col(origin(i))
    end
  end
end
