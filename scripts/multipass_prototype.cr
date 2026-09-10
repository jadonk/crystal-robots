# Standalone prototype of the progressive multipass tokenizer described in
# docs/PARSER.md. It is NOT wired into the build; it exists to prove the
# reduction schedule on the real example robots before the real
# Compiler::Parser is reworked.
#
#   crystal run scripts/multipass_prototype.cr -- examples/counter.cr
#   crystal run scripts/multipass_prototype.cr -- --trace 'puts 2+(1+2)//2*4'
#
# Every token kind is one reserved Unicode glyph. Pass 0 turns text into a
# glyph string. Every later pass applies exactly ONE grammar rule (the
# highest-priority rule that matches anywhere) to the whole glyph string,
# replacing each non-overlapping match with a single glyph, and records the
# matched span as the children of the new node. The loop stops when no rule
# matches; success means the string is the single Program glyph.

module MP
  enum T : Int32
    Invalid = 0x1F30B # 🌋
    String  = 0x1F40D # 🐍
    Number  =  0x2116 # №
    Ident   = 0x1D465 # 𝑥
    Newline =  0x23CE # ⏎
    Comma   =  0xFF0C # ，

    OpenParen  = 0x27EE # ⟮
    CloseParen = 0x27EF # ⟯

    Assign    = 0xFF1D # ＝
    AddAssign = 0x2795 # ➕
    SubAssign = 0x2796 # ➖
    MulAssign = 0x2716 # ✖
    ModAssign = 0x2052 # ⁒

    Add      = 0x2295 # ⊕
    Sub      = 0x2296 # ⊖
    Mul      = 0x2297 # ⊗
    FloorDiv = 0x2298 # ⊘
    Div      = 0xFF0F # ／
    Mod      = 0xFF05 # ％
    Eq       = 0x225F # ≟
    Ne       = 0x2260 # ≠
    Gt       = 0x227B # ≻
    Lt       = 0x227A # ≺
    Ge       = 0x227D # ≽
    Le       = 0x227C # ≼
    And      = 0x2227 # ∧
    Or       = 0x2228 # ∨

    KwIf     = 0x1F51C # 🔜
    KwElsif  = 0x1F518 # 🔘
    KwElse   = 0x1F517 # 🔗
    KwEnd    = 0x1F519 # 🔙
    KwWhile  = 0x1F523 # 🔣
    KwDef    = 0x1F515 # 🔕
    KwDo     = 0x1F516 # 🔖
    KwTrue   = 0x1F522 # 🔢
    KwFalse  = 0x1F51A # 🔚
    KwReturn =  0x21A9 # ↩
    KwBreak  = 0x1F513 # 🔓
    KwMain   = 0x1F3C1 # 🏁
    KwGlobal = 0x1F310 # 🌐
    KwUntil  = 0x1F502 # 🔂
    KwCase   = 0x1F514 # 🔔
    KwWhen   = 0x1F536 # 🔶

    ZeroArg = 0x2209 # ∉  damage speed loc_x loc_y sleep
    OneArg  = 0x220A # ∊  puts rand sqrt sin cos tan atan
    TwoArg  = 0x220B # ∋  scan cannon drive

    Expr = 0x1F611 # 😑

    IfHead    = 0x1F178 # 🅸
    ElsifHead = 0x1F174 # 🅴
    WhileHead = 0x1F186 # 🆆
    DefHead   = 0x1F173 # 🅳
    MainHead  = 0x1F17C # 🅼
    UntilHead = 0x1F184 # 🆄
    CaseHead  = 0x1F172 # 🅲
    WhenHead  = 0x1F182 # 🆂

    Stmt    = 0x2762 # ❢
    Program = 0x23F9 # ⏹

    def glyph : Char
      value.chr
    end
  end

  # A node is one glyph in one layer. Level 0 nodes point into the source
  # text (start/count are character offsets). Level k>0 nodes point into
  # layer k-1: their children are the glyph positions start...start+count of
  # that layer. `rule` names the grammar rule that produced the node so an
  # emitter knows which children matter.
  struct Node
    getter type : T, start : Int32, count : Int32, level : Int32, rule : Symbol

    def initialize(@type, @start, @count, @level, @rule)
    end
  end

  class Error < Exception
    getter line : Int32, col : Int32

    def initialize(msg, @line, @col)
      super("#{msg} at #{@line}:#{@col}")
    end
  end

  KEYWORDS = {
    "if" => T::KwIf, "elsif" => T::KwElsif, "else" => T::KwElse, "end" => T::KwEnd,
    "while" => T::KwWhile, "def" => T::KwDef, "do" => T::KwDo, "true" => T::KwTrue,
    "false" => T::KwFalse, "return" => T::KwReturn, "break" => T::KwBreak,
    "main" => T::KwMain, "global" => T::KwGlobal, "until" => T::KwUntil,
    "case" => T::KwCase, "when" => T::KwWhen,
    "damage" => T::ZeroArg, "speed" => T::ZeroArg, "loc_x" => T::ZeroArg,
    "loc_y" => T::ZeroArg, "sleep" => T::ZeroArg,
    "puts" => T::OneArg, "rand" => T::OneArg, "sqrt" => T::OneArg, "sin" => T::OneArg,
    "cos" => T::OneArg, "tan" => T::OneArg, "atan" => T::OneArg,
    "scan" => T::TwoArg, "cannon" => T::TwoArg, "drive" => T::TwoArg,
  }

  OPERATORS = {
    "==" => T::Eq, "!=" => T::Ne, "<=" => T::Le, ">=" => T::Ge, "&&" => T::And,
    "||" => T::Or, "+=" => T::AddAssign, "-=" => T::SubAssign, "*=" => T::MulAssign,
    "%=" => T::ModAssign, "//" => T::FloorDiv,
    "+" => T::Add, "-" => T::Sub, "*" => T::Mul, "/" => T::Div, "%" => T::Mod,
    "<" => T::Lt, ">" => T::Gt, "=" => T::Assign, "(" => T::OpenParen,
    ")" => T::CloseParen, "," => T::Comma,
  }

  # Pass 0: text to glyphs. Each entry is {regex, handler}. nil type = drop.
  LEX = [
    {/\A#[^\n]*/, nil},
    {/\A[ \t\r]+/, nil},
    {/\A(\n|;)+/, T::Newline},
    {/\A"[^"]*"/, T::String},
    {/\A[0-9]+/, T::Number},
    {/\A(==|!=|<=|>=|&&|\|\||\+=|-=|\*=|%=|\/\/|[-+*\/%<>=(),])/, T::Invalid}, # via OPERATORS
    {/\A[A-Za-z_][A-Za-z0-9_]*/, T::Ident},                                    # via KEYWORDS
  ]

  V = "[№🐍😑𝑥]" # anything that is already a value

  # Infix operator classes by precedence level, highest first.
  MULOPS = "⊗／⊘％"
  ADDOPS = "⊕⊖"
  CMPOPS = "≺≻≼≽"
  EQOPS  = "≟≠"
  ANDOP  = "∧"
  OROP   = "∨"

  # An infix rule at level L reduces `V op V` only when the left operand is not
  # preceded by an operator of level <= L (that operand belongs to the earlier
  # operator: left associativity) and the right operand is not followed by an
  # operator of level < L (that operand belongs to the tighter operator).
  def self.infix(ops : String, higher : String) : Regex
    ahead = higher.empty? ? "" : "(?![#{higher}])"
    Regex.new("(?<![#{higher}#{ops}])#{V}[#{ops}]#{V}#{ahead}")
  end

  # Grammar, in priority order. Each pass applies the FIRST rule in this list
  # that matches anywhere in the glyph string, to every non-overlapping match.
  GRAMMAR = [
    # headers first: a def/main header must never be mistaken for a call
    {:main_head, /🏁⟮🐍⟯🔖⏎/, T::MainHead},
    {:def_head, /🔕𝑥(⟮(𝑥(，𝑥)*)?⟯)?⏎/, T::DefHead},
    {:global, /🌐⟮𝑥，#{V}⟯⏎/, T::Stmt},
    # values
    {:literal, /[🔢🔚]/, T::Expr},
    {:call0, /∉/, T::Expr},
    {:call, /𝑥⟮(#{V}(，#{V})*)?⟯/, T::Expr},
    {:call1, /∊⟮#{V}⟯/, T::Expr},
    {:call2, /∋⟮#{V}，#{V}⟯/, T::Expr},
    {:paren, /⟮#{V}⟯/, T::Expr},
    {:neg, /(?<![№🐍😑𝑥⟯])⊖#{V}/, T::Expr},
    # infix, tightest first
    {:mul, infix(MULOPS, ""), T::Expr},
    {:add, infix(ADDOPS, MULOPS), T::Expr},
    {:cmp, infix(CMPOPS, MULOPS + ADDOPS), T::Expr},
    {:eq, infix(EQOPS, MULOPS + ADDOPS + CMPOPS), T::Expr},
    {:and, infix(ANDOP, MULOPS + ADDOPS + CMPOPS + EQOPS), T::Expr},
    {:or, infix(OROP, MULOPS + ADDOPS + CMPOPS + EQOPS + ANDOP), T::Expr},
    # command calls bind loosest of all expressions
    {:command1, /∊#{V}(?=[⏎⟯，])/, T::Expr},
    {:command2, /∋#{V}，#{V}(?=[⏎⟯，])/, T::Expr},
    # assignment is right associative: only when the value is complete
    {:assign, /𝑥＝#{V}(?=[⏎⟯，])/, T::Expr},
    {:opassign, /𝑥[➕➖✖⁒]#{V}(?=[⏎⟯，])/, T::Expr},
    # block headers
    {:if_head, /🔜#{V}⏎/, T::IfHead},
    {:elsif_head, /🔘#{V}⏎/, T::ElsifHead},
    {:while_head, /🔣#{V}⏎/, T::WhileHead},
    {:until_head, /🔂#{V}⏎/, T::UntilHead},
    {:case_head, /🔔#{V}⏎/, T::CaseHead},
    {:when_head, /🔶#{V}⏎/, T::WhenHead},
    # simple statements
    {:return, /↩#{V}?⏎/, T::Stmt},
    {:break, /🔓⏎/, T::Stmt},
    {:exprstmt, /#{V}⏎/, T::Stmt},
    # blocks: only when the body is fully reduced to statements
    {:if, /🅸❢*(🅴❢*)*(🔗⏎❢*)?🔙⏎/, T::Stmt},
    {:while, /🆆❢*🔙⏎/, T::Stmt},
    {:until, /🆄❢*🔙⏎/, T::Stmt},
    {:case, /🅲(🆂❢*)+(🔗⏎❢*)?🔙⏎/, T::Stmt},
    {:def, /🅳❢*🔙⏎/, T::Stmt},
    {:main, /🅼❢*🔙⏎/, T::Stmt},
    {:program, /\A❢+\z/, T::Program},
  ]

  class Program
    getter text : String
    getter ast = [] of Node
    # layers[k] = node index for each glyph position of pass k's output string
    getter layers = [] of Array(Int32)
    getter passes = [] of {Symbol, String}

    def initialize(@text)
    end

    def glyphs(layer : Array(Int32)) : String
      String.build { |io| layer.each { |i| io << ast[i].type.glyph } }
    end

    def lex : Array(Int32)
      layer = [] of Int32
      pos = 0
      chars = text.chars
      while pos < chars.size
        rest = text[pos..]
        matched = false
        LEX.each do |(regex, type)|
          m = regex.match(rest)
          next unless m
          matched = true
          value = m[0]
          t = type
          if t == T::Invalid
            t = OPERATORS[value]
          elsif t == T::Ident
            t = KEYWORDS.fetch(value, T::Ident)
          end
          if t && !(t == T::Newline && (layer.empty? || ast[layer.last].type == T::Newline))
            ast << Node.new(t, pos, value.size, 0, :lex)
            layer << ast.size - 1
          end
          pos += value.size
          break
        end
        unless matched
          l, c = line_col(pos)
          raise Error.new("Unexpected character #{chars[pos].inspect}", l, c)
        end
      end
      unless layer.empty? || ast[layer.last].type == T::Newline
        ast << Node.new(T::Newline, text.size, 0, 0, :lex)
        layer << ast.size - 1
      end
      layers << layer
      passes << {:lex, glyphs(layer)}
      layer
    end

    # One pass: the first grammar rule with any match, applied everywhere.
    def reduce_once(layer : Array(Int32)) : Array(Int32) | Nil
      s = glyphs(layer)
      GRAMMAR.each do |(name, regex, type)|
        matches = s.scan(regex)
        next if matches.empty?
        level = layers.size # this pass reads layers[level-1] == layer
        next_layer = [] of Int32
        cursor = 0
        matches.each do |m|
          b = m.begin(0)
          len = m[0].size
          (cursor...b).each { |i| next_layer << layer[i] }
          ast << Node.new(type, b, len, level, name)
          next_layer << ast.size - 1
          cursor = b + len
        end
        (cursor...layer.size).each { |i| next_layer << layer[i] }
        layers << next_layer
        passes << {name, glyphs(next_layer)}
        return next_layer
      end
      nil
    end

    def parse : Node
      layer = lex
      while (nxt = reduce_once(layer))
        layer = nxt
      end
      if layer.size == 1 && ast[layer[0]].type == T::Program
        ast[layer[0]]
      else
        bad = layer.find { |i| ast[i].type != T::Stmt } || layer[0]
        l, c = line_col(origin(bad))
        raise Error.new("Cannot reduce #{ast[bad].type.glyph} (#{ast[bad].type}) in #{glyphs(layer)}", l, c)
      end
    end

    # First source-text character covered by a node, following level-0 links.
    def origin(i : Int32) : Int32
      n = ast[i]
      return n.start if n.level == 0
      origin(layers[n.level - 1][n.start])
    end

    def line_col(pos : Int32) : {Int32, Int32}
      before = text[0, pos]
      {before.count('\n') + 1, pos - (before.rindex('\n') || -1)}
    end
  end
end

trace = ARGV.delete("--trace")
ARGV.each do |arg|
  src = File.exists?(arg) ? File.read(arg) : arg
  p = MP::Program.new(src)
  begin
    p.parse
    puts "OK   #{arg}: #{p.passes.size} passes, #{p.ast.size} nodes"
  rescue e : MP::Error
    puts "FAIL #{arg}: #{e.message}"
  end
  if trace
    p.passes.each_with_index { |(name, s), i| puts "  #{i.to_s.rjust(3)} #{name.to_s.ljust(11)} #{s}" }
  end
end
