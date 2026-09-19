require "./program"
require "./parser"
require "./interpreter"

# The WebAssembly emitter. Every module starts with the same 8 bytes: a
# 4-byte magic number spelling `\0asm` and a 4-byte version, followed by
# sections, each a section id byte, the section's byte length, and its own
# vector of entries.
#
# `WASM_Emitter.new(program).to_wasm` walks the AST that `Parser` built and
# exports `run`. This commit adds `def`, calls with arguments and `return`:
# each `def` becomes its own WASM function, with parameters as its first
# locals and any name assigned inside it that is not already a global
# becoming a further local, and `Ctx#ret` (a local holding the implicit
# return value) taking the place of `run`'s `drop` for the last-expression
# rule Crystal-like languages use.
#
# https://webassembly.github.io/spec/core/binary/modules.html
module CrystalRobots::Compiler
  class WASM_Emitter
    # https://webassembly.github.io/spec/core/binary/modules.html#sections
    enum Section : UInt8
      Type   =  1
      Import =  2
      Func   =  3
      Global =  6
      Export =  7
      Code   = 10
    end

    # https://webassembly.github.io/spec/core/binary/types.html
    enum Valtype : UInt8
      I32 = 0x7f
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes : UInt8
      Block      = 0x02
      Loop       = 0x03
      If         = 0x04
      Else       = 0x05
      End        = 0x0b
      Br         = 0x0c
      Br_if      = 0x0d
      Return     = 0x0f
      Call       = 0x10
      Drop       = 0x1a
      Local_get  = 0x20
      Local_set  = 0x21
      Local_tee  = 0x22
      Global_get = 0x23
      Global_set = 0x24
      I32_const  = 0x41
      I32_eqz    = 0x45
      I32_eq     = 0x46
      I32_ne     = 0x47
      I32_lt_s   = 0x48
      I32_gt_s   = 0x4a
      I32_le_s   = 0x4c
      I32_ge_s   = 0x4e
      I32_add    = 0x6a
      I32_sub    = 0x6b
      I32_mul    = 0x6c
      I32_div_s  = 0x6d
      I32_rem_s  = 0x6f
      I32_and    = 0x71
      I32_or     = 0x72
      I32_xor    = 0x73
    end

    BlockVoid = 0x40_u8

    class Unsupported < Exception
    end

    # Per-function compilation state. `depth` and `loops` are as before;
    # `locals` maps a name to its local index (seeded with a function's
    # parameters, growing as assignments introduce more); `ret` is the
    # local `return` and the implicit last-expression-executed rule write
    # to, `-1` at the top level where there is no function to return from.
    private class Ctx
      getter locals = {} of String => Int32
      property depth = 0
      getter loops = [] of Int32
      getter in_def : Bool
      property ret : Int32 = -1
      property temps = 0

      def initialize(@in_def : Bool = false)
      end
    end

    enum ExportType : UInt8
      Func = 0x00
    end

    FunctionType      = 0x60
    MagicModuleHeader = Bytes[0x00, 'a'.ord, 's'.ord, 'm'.ord]
    ModuleVersion     = Bytes[0x01, 0x00, 0x00, 0x00]

    def self.minimal_module : Bytes
      MagicModuleHeader + ModuleVersion
    end

    # https://en.wikipedia.org/wiki/LEB128
    def self.unsignedLEB128(n : Int32) : Bytes
      buffer = Bytes[]
      loop do
        byte = n & 0x7f
        n = n >> 7
        byte |= 0x80 if n != 0
        buffer += Bytes[byte]
        break if n == 0
      end
      buffer
    end

    # https://en.wikipedia.org/wiki/LEB128, signed variant, for constants
    # that may be negative.
    def self.signedLEB128(n : Int32) : Bytes
      buffer = Bytes[]
      more = true
      while more
        byte = (n & 0x7f).to_u8
        n = n >> 7
        if (n == 0 && (byte & 0x40) == 0) || (n == -1 && (byte & 0x40) != 0)
          more = false
        else
          byte = byte | 0x80
        end
        buffer += Bytes[byte]
      end
      buffer
    end

    def self.encodeVector(entries : Array(Bytes)) : Bytes
      unsignedLEB128(entries.size) + entries.reduce(Bytes[]) { |a, b| a + b }
    end

    def self.encodeString(string : String) : Bytes
      unsignedLEB128(string.bytesize) + string.to_slice
    end

    def self.createSection(type : Section, data : Bytes) : Bytes
      Bytes[type.value] + unsignedLEB128(data.size) + data
    end

    # Builtins in import order, with how many `i32` arguments each takes.
    IMPORTS = {
      "puts" => 1, "scan" => 2, "cannon" => 2, "drive" => 2,
      "damage" => 0, "speed" => 0, "loc_x" => 0, "loc_y" => 0, "sleep" => 0,
      "rand" => 1, "sqrt" => 1, "sin" => 1, "cos" => 1, "tan" => 1, "atan" => 1,
    }

    getter program : Program
    getter imports : Array(String)
    getter functions : Array(String)

    # `costs` is `nil` by default: no `env.tick` calls, the module this
    # emitter has always produced. Pass an `Interpreter::Costs` to charge
    # cycles at the same points the interpreter does, so a differential
    # spec can run the same robot through both and compare totals.
    def initialize(@program : Program, @costs : Interpreter::Costs? = nil)
      @globals = [] of String
      @functions = [] of String
      @arity = {} of String => Int32
      @extra_arities = [] of Int32
      @program.children(@program.root).each do |stmt|
        case @program[stmt].rule
        when :global
          # global(name, init): children are 🌐 ⟮ name ， init ⟯ ⏎
          @globals << @program.value(@program.arg(stmt, 2))
        when :def
          head = @program.children(stmt)[0]
          idents = @program.children(head).select { |i| @program.type(i) == Type::Identifier }
          name = @program.lexeme(idents[0])
          @functions << name
          @arity[name] = idents.size - 1
        when :exprstmt
          # A plain top-level assignment (`C1X = 10`) is an implicit
          # global too -- the shape the example robots use for constants,
          # never wrapped in `global(...)`.
          expr = @program.arg(stmt, 0)
          if @program[expr].rule == :assign
            name = @program.value(@program.arg(expr, 0))
            @globals << name unless @globals.includes?(name)
          end
        end
      end
      used = Set(String).new
      @program.ast.each do |n|
        used << @program.value(n) if n.level == 0 && {Type::ZeroArgMethod, Type::OneArgMethod, Type::TwoArgMethod}.includes?(n.type)
      end
      imports = IMPORTS.keys.select { |name| used.includes?(name) }
      @imports = @costs ? ["tick"] + imports : imports
      @functions.each { |name| type_for(@arity[name]) } # populate @extra_arities before type_section is built
    end

    private def import_index(name : String) : Int32
      @imports.index(name) || raise Unsupported.new("no import for #{name}")
    end

    private def run_index : Int32
      @imports.size
    end

    private def function_index(name : String) : Int32
      run_index + 1 + (@functions.index(name) || raise Unsupported.new("no function #{name}"))
    end

    private def op(code : Opcodes) : Bytes
      Bytes[code.value]
    end

    private def const(n : Int32) : Bytes
      op(Opcodes::I32_const) + WASM_Emitter.signedLEB128(n)
    end

    private def call(i : Int32) : Bytes
      op(Opcodes::Call) + WASM_Emitter.unsignedLEB128(i)
    end

    private def cost : Interpreter::Costs
      @costs || Interpreter::Costs.new
    end

    # `env.tick(n)` when cycle accounting is on and n > 0: a no-op,
    # returning empty bytes, exactly reproducing every module this
    # emitter produced before `costs` existed.
    private def tick(n : Int32) : Bytes
      return Bytes[] if @costs.nil? || n <= 0
      const(n) + call(import_index("tick")) + op(Opcodes::Drop)
    end

    private def local_get(i : Int32) : Bytes
      op(Opcodes::Local_get) + WASM_Emitter.unsignedLEB128(i)
    end

    private def local_set(i : Int32) : Bytes
      op(Opcodes::Local_set) + WASM_Emitter.unsignedLEB128(i)
    end

    private def local_tee(i : Int32) : Bytes
      op(Opcodes::Local_tee) + WASM_Emitter.unsignedLEB128(i)
    end

    # Types 0..2 are one per builtin arity (0, 1 or 2 `i32` params, one
    # `i32` result, reused for user functions of the same arity); type 3
    # is `run`'s, `() -> ()`. A user function of a larger arity gets one
    # more type each, in order of first use.
    RUN_TYPE = 3

    private def type_for(arity : Int32) : Int32
      return arity if arity <= 2
      @extra_arities << arity unless @extra_arities.includes?(arity)
      4 + @extra_arities.index!(arity)
    end

    def type_section : Bytes
      fixed = [
        Bytes[FunctionType, 0, 1, Valtype::I32.value],                                         # 0: () -> i32
        Bytes[FunctionType, 1, Valtype::I32.value, 1, Valtype::I32.value],                     # 1: (i32) -> i32
        Bytes[FunctionType, 2, Valtype::I32.value, Valtype::I32.value, 1, Valtype::I32.value], # 2: (i32, i32) -> i32
        Bytes[FunctionType, 0, 0],                                                             # 3: () -> ()
      ]
      extra = @extra_arities.map do |arity|
        Bytes[FunctionType] + WASM_Emitter.unsignedLEB128(arity) + Bytes.new(arity, Valtype::I32.value) + Bytes[1, Valtype::I32.value]
      end
      WASM_Emitter.createSection(Section::Type, WASM_Emitter.encodeVector(fixed + extra))
    end

    # `tick` isn't a CROBOTS builtin the program calls, so it isn't in
    # `IMPORTS`; it takes one `i32` (the cycles charged) and, like every
    # other import, returns one so it shares a type with the arity-1
    # builtins.
    private def import_arity(name : String) : Int32
      name == "tick" ? 1 : IMPORTS[name]
    end

    def import_section : Bytes
      WASM_Emitter.createSection(Section::Import,
        WASM_Emitter.encodeVector(@imports.map { |name|
          WASM_Emitter.encodeString("env") + WASM_Emitter.encodeString(name) + Bytes[ExportType::Func.value, import_arity(name).to_u8]
        }))
    end

    def func_section : Bytes
      types = [RUN_TYPE] + @functions.map { |name| type_for(@arity[name]) }
      WASM_Emitter.createSection(Section::Func, WASM_Emitter.encodeVector(types.map { |t| Bytes[t.to_u8] }))
    end

    # One mutable i32 global per `global(...)` declaration, all initialized
    # to 0; `run` sets each to its declared init expression's value.
    def global_section : Bytes
      return Bytes[] if @globals.empty?
      entry = Bytes[Valtype::I32.value, 1] + const(0) + op(Opcodes::End)
      WASM_Emitter.createSection(Section::Global, WASM_Emitter.encodeVector(@globals.map { entry }))
    end

    private def global_index(name : String) : Int32
      @globals.index(name) || raise Unsupported.new("unknown global #{name}")
    end

    private def global_get(name : String) : Bytes
      op(Opcodes::Global_get) + WASM_Emitter.unsignedLEB128(global_index(name))
    end

    private def global_set(name : String) : Bytes
      op(Opcodes::Global_set) + WASM_Emitter.unsignedLEB128(global_index(name))
    end

    # Read a variable: a local (a parameter, or a name already assigned in
    # this function) first, then a global.
    private def variable_get(name : String, ctx : Ctx) : Bytes
      if (i = ctx.locals[name]?)
        local_get(i)
      elsif @globals.includes?(name)
        global_get(name)
      else
        raise Unsupported.new("undefined variable #{name}")
      end
    end

    # An identifier in value position: a variable fetch, or -- if it is
    # not a variable at all -- a call to a zero-parameter function, the
    # `run`/`change`/`new_corner` style bare calls the example robots use.
    private def identifier_get(name : String, ctx : Ctx) : Bytes
      if !ctx.locals.has_key?(name) && !@globals.includes?(name) && @arity[name]? == 0
        tick(cost.call) + call(function_index(name))
      else
        tick(cost.fetch) + variable_get(name, ctx)
      end
    end

    private def new_local(ctx : Ctx, name : String) : Int32
      ctx.locals[name] = ctx.locals.size
    end

    # Store the value on top of the stack into a variable and leave a copy
    # of it there: a global that already exists goes to `global.set` then
    # a re-fetch (WASM globals have no `tee`); otherwise it is a local,
    # `local.tee`, first assignment inside a function introducing it.
    private def variable_tee(name : String, ctx : Ctx) : Bytes
      if @globals.includes?(name) && !ctx.locals.has_key?(name)
        global_set(name) + global_get(name)
      else
        local_tee(ctx.locals[name]? || new_local(ctx, name))
      end
    end

    def export_section : Bytes
      WASM_Emitter.createSection(Section::Export,
        WASM_Emitter.encodeVector([
          WASM_Emitter.encodeString("run") + Bytes[ExportType::Func.value] + WASM_Emitter.unsignedLEB128(run_index),
        ]))
    end

    # Emit code that leaves the value of expression node `i` on the stack.
    def expression(i : Int32, ctx : Ctx) : Bytes
      n = @program[i]
      case n.rule
      when :lex
        n.type == Type::Identifier ? identifier_get(@program.value(n), ctx) : tick(cost.fetch) + const(@program.value(n).to_i32)
      when :literal
        tick(cost.fetch) + const(@program.type(@program.arg(i, 0)) == Type::TrueKeyword ? 1 : 0)
      when :assign
        name = @program.value(@program.arg(i, 0))
        expression(@program.arg(i, 2), ctx) + tick(cost.store) + variable_tee(name, ctx)
      when :opassign
        name = @program.value(@program.arg(i, 0))
        opt = case @program.type(@program.arg(i, 1))
              when Type::AddAssign then Type::AddOperator
              when Type::SubAssign then Type::SubOperator
              when Type::MulAssign then Type::MulOperator
              else                      Type::ModOperator
              end
        binary(opt, variable_get(name, ctx), expression(@program.arg(i, 2), ctx)) +
          tick(cost.fetch + cost.operator + cost.store) + variable_tee(name, ctx)
      when :paren
        expression(@program.arg(i, 1), ctx)
      when :neg
        const(0) + expression(@program.arg(i, 1), ctx) + op(Opcodes::I32_sub) + tick(cost.operator)
      when :mul, :add, :cmp, :eq, :and, :or
        binary(@program.type(@program.arg(i, 1)), expression(@program.arg(i, 0), ctx), expression(@program.arg(i, 2), ctx)) + tick(cost.operator)
      when :call0
        tick(cost.builtin) + call(import_index(@program.lexeme(i)))
      when :command1, :call1
        arg_index = n.rule == :call1 ? 2 : 1
        expression(@program.arg(i, arg_index), ctx) + tick(cost.builtin) + call(import_index(@program.lexeme(@program.arg(i, 0))))
      when :command2, :call2
        a, b = n.rule == :call2 ? {2, 4} : {1, 3}
        expression(@program.arg(i, a), ctx) + expression(@program.arg(i, b), ctx) +
          tick(cost.builtin) + call(import_index(@program.lexeme(@program.arg(i, 0))))
      when :call
        kids = @program.children(i)
        name = @program.lexeme(kids[0])
        args = kids[2..].reject { |k| {Type::CloseParen, Type::Comma}.includes?(@program.type(k)) }
        args.reduce(Bytes[]) { |code, a| code + expression(a, ctx) } + tick(cost.call) + call(function_index(name))
      else
        raise Unsupported.new("expression #{n.rule} is not supported in WASM")
      end
    end

    # `/` and `//` both truncate toward zero for now, and none of the four
    # trap on division by zero the way WASM's own `i32.div_s` does; CROBOTS's
    # floored division and its divide-by-zero-is-zero rule are a later
    # commit's problem, once a robot can actually divide by something that
    # might be zero.
    private def binary(opt : Type, left : Bytes, right : Bytes) : Bytes
      case opt
      when Type::AddOperator then left + right + op(Opcodes::I32_add)
      when Type::SubOperator then left + right + op(Opcodes::I32_sub)
      when Type::MulOperator then left + right + op(Opcodes::I32_mul)
      when Type::DivOperator, Type::FloorDivOperator
        left + right + op(Opcodes::I32_div_s)
      when Type::ModOperator then left + right + op(Opcodes::I32_rem_s)
      when Type::EqOperator  then left + right + op(Opcodes::I32_eq)
      when Type::NeOperator  then left + right + op(Opcodes::I32_ne)
      when Type::LtOperator  then left + right + op(Opcodes::I32_lt_s)
      when Type::GtOperator  then left + right + op(Opcodes::I32_gt_s)
      when Type::LeOperator  then left + right + op(Opcodes::I32_le_s)
      when Type::GeOperator  then left + right + op(Opcodes::I32_ge_s)
      when Type::AndOperator
        left + const(0) + op(Opcodes::I32_ne) + right + const(0) + op(Opcodes::I32_ne) + op(Opcodes::I32_and)
      when Type::OrOperator
        left + const(0) + op(Opcodes::I32_ne) + right + const(0) + op(Opcodes::I32_ne) + op(Opcodes::I32_or)
      when Type::XorOperator then left + right + op(Opcodes::I32_xor)
      else
        raise Unsupported.new("operator #{opt} is not supported in WASM")
      end
    end

    # Statements a block (`while`/`until`/`if`/`def`) or `run` can contain.
    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    def statement(stmt : Int32, ctx : Ctx) : Bytes
      return Bytes[] if @program[stmt].rule == :def # compiled separately, see function_body
      tick(cost.statement) + case @program[stmt].rule
      when :global
        expression(@program.arg(stmt, 4), ctx) + global_set(@program.value(@program.arg(stmt, 2)))
      when :while
        loop_statement(stmt, ctx, while_true: true)
      when :until
        loop_statement(stmt, ctx, while_true: false)
      when :break
        exit = ctx.loops.last? || raise Unsupported.new("break outside of a loop")
        tick(cost.branch) + op(Opcodes::Br) + WASM_Emitter.unsignedLEB128(ctx.depth - exit)
      when :return
        raise Unsupported.new("return outside of a function") unless ctx.in_def
        kids = @program.children(stmt)
        value = kids.size > 2 ? expression(kids[1], ctx) : const(0)
        value + tick(cost.branch) + op(Opcodes::Return)
      when :if
        if_statement(stmt, ctx)
      when :case
        case_statement(stmt, ctx)
      when :exprstmt
        value = expression(@program.arg(stmt, 0), ctx)
        ctx.in_def ? value + local_set(ctx.ret) : value + op(Opcodes::Drop)
      else
        raise Unsupported.new("statement #{@program[stmt].rule} is not supported in WASM")
      end
    end

    # `while`/`until`: `block { loop { cond; br_if exit; body; br loop } }`.
    # `while` exits when the condition is false (`i32.eqz` first); `until`
    # exits when it is true. A loop is not itself a value, so it resets the
    # implicit return value to 0 the way `end` of a Ruby-like `while` does.
    private def loop_statement(stmt : Int32, ctx : Ctx, while_true : Bool) : Bytes
      head = @program.children(stmt)[0]
      cond = @program.arg(head, 1)
      code = op(Opcodes::Block) + Bytes[BlockVoid]
      ctx.depth += 1
      exit = ctx.depth
      ctx.loops << exit
      code += op(Opcodes::Loop) + Bytes[BlockVoid]
      ctx.depth += 1
      code += expression(cond, ctx)
      code += op(Opcodes::I32_eqz) if while_true
      code += tick(cost.branch)
      code += op(Opcodes::Br_if) + WASM_Emitter.unsignedLEB128(ctx.depth - exit)
      body_of(stmt).each { |s| code += statement(s, ctx) }
      code += op(Opcodes::Br) + WASM_Emitter.unsignedLEB128(0)
      ctx.depth -= 1
      code += op(Opcodes::End) # loop
      ctx.loops.pop
      ctx.depth -= 1
      code += op(Opcodes::End) # block
      code += const(0) + local_set(ctx.ret) if ctx.in_def
      code
    end

    # `if`/`elsif`/`else`, each a `{condition, statements}` branch (`else`'s
    # condition is `nil`), as nested WASM `if { ... } else { ... }` blocks.
    private def if_statement(stmt : Int32, ctx : Ctx) : Bytes
      branches = [] of {Int32?, Array(Int32)}
      @program.children(stmt).each do |k|
        case @program.type(k)
        when Type::IfHead, Type::ElsifHead
          branches << {@program.arg(k, 1), [] of Int32}
        when Type::ElseKeyword
          branches << {nil, [] of Int32}
        when Type::Statement
          branches.last[1] << k
        end
      end
      emit_branches(branches, ctx)
    end

    private def emit_branches(branches : Array({Int32?, Array(Int32)}), ctx : Ctx) : Bytes
      return Bytes[] if branches.empty?
      cond, stmts = branches[0]
      if cond.nil?
        return stmts.reduce(Bytes[]) { |code, s| code + statement(s, ctx) }
      end
      code = expression(cond, ctx) + tick(cost.branch) + op(Opcodes::If) + Bytes[BlockVoid]
      ctx.depth += 1
      code = stmts.reduce(code) { |c, s| c + statement(s, ctx) }
      rest = branches[1..]
      unless rest.empty?
        code += op(Opcodes::Else) + emit_branches(rest, ctx)
      end
      ctx.depth -= 1
      code + op(Opcodes::End)
    end

    # `case`: the subject goes into a temporary local once; each `when`
    # compares to it with `i32.eq`. Structurally the same nested
    # `if`/`else` chain as `if`/`elsif`/`else`, just with a synthesized
    # condition instead of one already in the AST.
    private def case_statement(stmt : Int32, ctx : Ctx) : Bytes
      kids = @program.children(stmt)
      subject = new_local(ctx, "$case#{ctx.temps += 1}")
      code = expression(@program.arg(kids[0], 1), ctx) + local_set(subject)
      branches = [] of {Int32?, Array(Int32)}
      @program.children(stmt).each do |k|
        case @program.type(k)
        when Type::WhenHead
          branches << {@program.arg(k, 1), [] of Int32}
        when Type::ElseKeyword
          branches << {nil, [] of Int32}
        when Type::Statement
          branches.last[1] << k
        end
      end
      code + emit_case_branches(branches, subject, ctx)
    end

    private def emit_case_branches(branches : Array({Int32?, Array(Int32)}), subject : Int32, ctx : Ctx) : Bytes
      return Bytes[] if branches.empty?
      cond, stmts = branches[0]
      if cond.nil?
        return stmts.reduce(Bytes[]) { |code, s| code + statement(s, ctx) }
      end
      code = local_get(subject) + expression(cond, ctx) + op(Opcodes::I32_eq) + tick(cost.branch) + op(Opcodes::If) + Bytes[BlockVoid]
      ctx.depth += 1
      code = stmts.reduce(code) { |c, s| c + statement(s, ctx) }
      rest = branches[1..]
      unless rest.empty?
        code += op(Opcodes::Else) + emit_case_branches(rest, subject, ctx)
      end
      ctx.depth -= 1
      code + op(Opcodes::End)
    end

    private def locals_decl(count : Int32) : Bytes
      count == 0 ? Bytes[0] : Bytes[1] + WASM_Emitter.unsignedLEB128(count) + Bytes[Valtype::I32.value]
    end

    # `run`: every top-level statement except `def` (compiled separately)
    # and `main` (deferred: its body runs last, as the entry point).
    private def run_body : Bytes
      ctx = Ctx.new
      main_stmts = [] of Int32
      code = Bytes[]
      body_of(@program.root).each do |stmt|
        case @program[stmt].rule
        when :def
        when :main
          main_stmts = body_of(stmt)
        else
          code += statement(stmt, ctx)
        end
      end
      main_stmts.each { |s| code += statement(s, ctx) }
      code += op(Opcodes::End)
      locals_decl(ctx.locals.size) + code
    end

    # One WASM function per `def`: its parameters seed `ctx.locals`, a
    # further local (`ctx.ret`) holds the implicit return value, and the
    # body ends by pushing it.
    private def function_body(name : String) : Bytes
      stmt = @program.children(@program.root).find! do |s|
        @program[s].rule == :def && @program.lexeme(@program.children(@program.arg(s, 0))[1]) == name
      end
      head = @program.arg(stmt, 0)
      params = @program.children(head).select { |i| @program.type(i) == Type::Identifier }[1..].map { |i| @program.lexeme(i) }
      ctx = Ctx.new(in_def: true)
      params.each { |p| ctx.locals[p] = ctx.locals.size }
      ctx.ret = new_local(ctx, "$ret")
      code = Bytes[]
      body_of(stmt).each { |s| code += statement(s, ctx) }
      code += local_get(ctx.ret) + op(Opcodes::End)
      locals_decl(ctx.locals.size - params.size) + code
    end

    def code_section : Bytes
      bodies = [run_body] + @functions.map { |name| function_body(name) }
      WASM_Emitter.createSection(Section::Code,
        WASM_Emitter.encodeVector(bodies.map { |b| WASM_Emitter.unsignedLEB128(b.size) + b }))
    end

    def to_wasm : Bytes
      WASM_Emitter.minimal_module + type_section + import_section + func_section +
        global_section + export_section + code_section
    end
  end
end
