# The progressive multipass tokenizer

Status 2026-09-10: implemented in `src/compiler/parser.cr` and
`src/compiler/compiler.cr` (ported from `scripts/multipass_prototype.cr`,
which is kept as the standalone reference). All six example robots reduce to
the single Program glyph with correct precedence and associativity;
`bin/crystal-robots -t FILE` prints the derivation.

## 1. The idea, restated

Every token kind is one reserved Unicode glyph (the `Type` enum). Parsing is
string rewriting:

- **Pass 0** turns source text into a glyph string with the lexical regexes.
- **Every later pass** applies one grammar rule, written as a regex over
  glyphs, to the whole string. Each match collapses to a single new glyph.
- The program is parsed when the string is the single glyph `⏹`.

Each pass output is a string, so `Program#to_s` can show the whole
derivation, one line per pass. That is the teaching visual.

```
   0 lex         ∊№⊕⟮№⊕№⟯⊘№⊗№⏎        puts 2+(1+2)//2*4
   1 add         ∊№⊕⟮😑⟯⊘№⊗№⏎
   2 paren       ∊№⊕😑⊘№⊗№⏎
   3 mul         ∊№⊕😑⊗№⏎
   4 mul         ∊№⊕😑⏎
   5 add         ∊😑⏎
   6 command1    😑⏎
   7 exprstmt    ❢
   8 program     ⏹
```

## 2. What made it dizzy, and the answer to each

1. **Precedence is global, not positional.** Trying rules in order *at each
   index* (what `Parser.tokenize` does today) reduces `1+2*3` as `(1+2)*3`,
   because at index 0 the `+` rule matches before the scanner ever reaches
   the `*`. The fix is the **reduction schedule**: a pass picks the first
   rule in priority order that matches *anywhere* in the string and applies
   it to every non-overlapping match. Then the next pass starts again from
   the top of the rule list. Higher-precedence operators therefore always
   reduce before lower ones, no matter where they sit.

2. **Associativity needs guards.** With the schedule alone, `(1+2)//2*4`
   reduces `2*4` first because the left operand of `//` is still `⟯`. An
   infix rule at level L may only fire when the left operand is not preceded
   by an operator of level ≤ L and the right operand is not followed by an
   operator of level < L. Both are one regex lookaround each:

   ```
   (?<![⊗／⊘％⊕⊖]) V [⊕⊖] V (?![⊗／⊘％])      # the add rule
   ```

   Assignment is right associative and only fires when its value is
   complete: `𝑥＝V(?=[⏎⟯，])`. `x = y = 1` then reduces inner first.

3. **Headers before calls.** `def go(a, b)` looks like a call
   `go(a, b)`. Header rules (`def`, `main`, `global`) sit at the top of the
   rule list so the call rule never sees them.

4. **Statements need a terminator.** Newlines and `;` become one `⏎` glyph
   (runs collapse to one, leading `⏎` dropped, one appended at end of input).
   A value followed by `⏎` is a statement; a block header is
   `keyword V ⏎`. Without the terminator there is no way to tell where an
   `if` condition ends.

5. **Blocks reduce innermost first for free.** A block rule such as
   `🆆❢*🔙⏎` only matches when its body is entirely statements, so an inner
   `if` inside a `while` collapses first, then the `while`. No nesting
   bookkeeping is needed.

6. **Assignment inside a condition** (`while (range = scan(a, r)) > 0`)
   works because assignment is an expression: `𝑥＝😑` → `😑`, then paren,
   then compare, then the `while` header.

7. **Values are one character class.** `V = [№🐍😑𝑥]`: number, string,
   reduced expression, identifier. Every rule that consumes an operand uses
   `V`, so the grammar stays flat.

## 3. Glyph additions

The existing `Type` glyphs stay. New ones the examples need:

| Glyph | Type | Lexeme |
| --- | --- | --- |
| `𝑥` | Ident | any identifier or constant |
| `⏎` | Newline | newline, `;`, end of input |
| `，` | Comma | `,` |
| `＝ ➕ ➖ ✖ ⁒` | Assign, AddAssign, SubAssign, MulAssign, ModAssign | `= += -= *= %=` |
| `／ ％ ≽ ≼` | Div, Mod, Ge, Le | `/ % >= <=` |
| `∧ ∨` | And, Or | `&& \|\|` (were `&` and `\|`) |
| `↩ 🔓 🏁 🌐 🔂 🔔 🔶` | Return, Break, Main, Global, Until, Case, When | keywords |
| `🅸 🅴 🆆 🆄 🅲 🆂 🅳 🅼` | IfHead, ElsifHead, WhileHead, UntilHead, CaseHead, WhenHead, DefHead, MainHead | intermediate |
| `❢` | Stmt | any statement (replaces the three arity variants) |

Builtins keep their arity glyphs: `∉` zero args (`damage speed loc_x loc_y
sleep`), `∊` one (`puts rand sqrt sin cos tan atan`), `∋` two (`scan cannon
drive`). `main` is a keyword, not a two-argument builtin.

## 4. Rule list (priority order)

```
main_head   🏁⟮🐍⟯🔖⏎            → 🅼
def_head    🔕𝑥(⟮(𝑥(，𝑥)*)?⟯)?⏎   → 🅳
global      🌐⟮𝑥，V⟯⏎            → ❢
literal     [🔢🔚]               → 😑
call0       ∉                    → 😑
call        𝑥⟮(V(，V)*)?⟯         → 😑   user function call
call1/call2 ∊⟮V⟯  ∋⟮V，V⟯        → 😑
paren       ⟮V⟯                  → 😑
neg         (?<![V⟯])⊖V          → 😑
mul add cmp eq and or            → 😑   infix with guards (section 2.2)
command1/2  ∊V  ∋V，V  (+ lookahead)  → 😑   puts 1+2
assign      𝑥＝V(?=[⏎⟯，])        → 😑
opassign    𝑥[➕➖✖⁒]V(?=[⏎⟯，])   → 😑
*_head      🔜V⏎ 🔘V⏎ 🔣V⏎ 🔂V⏎ 🔔V⏎ 🔶V⏎ → 🅸 🅴 🆆 🆄 🅲 🆂
return      ↩V?⏎                 → ❢
break       🔓⏎                  → ❢
exprstmt    V⏎                   → ❢
if          🅸❢*(🅴❢*)*(🔗⏎❢*)?🔙⏎ → ❢
while/until 🆆❢*🔙⏎  🆄❢*🔙⏎     → ❢
case        🅲(🆂❢*)+(🔗⏎❢*)?🔙⏎  → ❢
def/main    🅳❢*🔙⏎  🅼❢*🔙⏎     → ❢
program     \A❢+\z               → ⏹
```

Known, accepted gaps: `puts(1) + 2` parses as `puts(1 + 2)` (Crystal itself
warns about that form), no `next`/`for`/`!`, no float literals, one string
literal use (`main("Name")`).

## 5. Data model, mapped onto the existing `Program`

The current `Program` already has the right pieces; the prototype just pins
down what each field means.

- `source` stays the source text followed by the glyph string of every
  pass, and `pass[k]` stays the offset where pass k's string starts. So the
  program still "looks like a string" and `to_s` prints the derivation.
- `Node(type, start, count)` keeps its meaning for level 0 (text offsets).
  For a node made in pass k, `start`/`count` are positions in pass k-1's
  string. Store them as absolute offsets into `source` (`pass[k-1] + pos`)
  so `Program#value(node)` returns the child glyph run for every level.
- `nxt` goes away. In its place each pass keeps a **layer**: the array of
  node indexes, one per glyph position of that pass's string. This is the
  missing link that the `TODO pc = PC.new(p.pc.pass - 1, i)` comments were
  reaching for. `arg(n)` of a node becomes
  `ast[layers[level - 1][pos + n]]`, and `level` is found from `start` with
  `pass`.
- Each node also records the **rule name** that produced it (`:if`,
  `:call2`, `:assign`, ...). Emitters and the interpreter dispatch on that
  instead of re-deriving shape from glyphs.
- `GrammarRule(regex, type)` stays; `MappingType` collapses to the default
  mapping because parentheses and program are just rules like any other.
- `Parser.tokenize(p, src)` becomes `reduce_once`: one pass, returns the new
  string or nil when no rule matched. `Parser#initialize` keeps its loop.
- The interpreter walks the tree recursively through `children`/`arg(n)`;
  the old `pc`/`stack` fields are gone.

## 6. Errors

When no rule matches and the string is not `⏹`, the leftmost glyph that is
not `❢` is the culprit. Follow `layers` down to its level-0 ancestor and
report the source line and column, for example
`Cannot reduce 🔙 (KwEnd) at 12:1`. Lexical errors report the offending
character the same way. Both come out of the prototype today.

## 7. Cost

Each pass is one regex scan over a string a few hundred glyphs long; the
examples need 4 to 41 passes. That is far below anything a browser or CGI
request would notice, and the pass count is exactly the number of lines in
the teaching trace.
