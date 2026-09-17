require "./program"
require "./parser"

# The WebAssembly emitter. Every module starts with the same 8 bytes: a
# 4-byte magic number spelling `\0asm` and a 4-byte version, followed by
# sections, each a section id byte, the section's byte length, and its own
# vector of entries.
#
# `WASM_Emitter.new(program).to_wasm` walks the AST that `Parser` built.
# The module it produces imports `env.puts` and exports `run`, which calls
# it once per top-level statement; this commit adds `if`/`elsif`/`else`,
# compiled to a chain of nested WASM `if`/`else` blocks.
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
      Call       = 0x10
      Drop       = 0x1a
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
    end

    BlockVoid = 0x40_u8

    class Unsupported < Exception
    end

    # Per-`run`/function compilation state: how many WASM labels
    # (block/loop) currently enclose the code being emitted, and the label
    # depth `break` should branch to for each loop it is nested in.
    private class Ctx
      property depth = 0
      getter loops = [] of Int32
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

    getter program : Program

    def initialize(@program : Program)
      @globals = [] of String
      @program.children(@program.root).each do |stmt|
        # global(name, init): children are 🌐 ⟮ name ， init ⟯ ⏎
        @globals << @program.value(@program.arg(stmt, 2)) if @program[stmt].rule == :global
      end
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

    PUTS_IMPORT_INDEX = 0
    RUN_FUNC_INDEX    = 1 # after the one import

    def type_section : Bytes
      WASM_Emitter.createSection(Section::Type,
        WASM_Emitter.encodeVector([
          Bytes[FunctionType, 1, Valtype::I32.value, 1, Valtype::I32.value], # 0: (i32) -> i32  puts
          Bytes[FunctionType, 0, 0],                                         # 1: () -> ()      run
        ]))
    end

    def import_section : Bytes
      WASM_Emitter.createSection(Section::Import,
        WASM_Emitter.encodeVector([
          WASM_Emitter.encodeString("env") + WASM_Emitter.encodeString("puts") + Bytes[ExportType::Func.value, 0],
        ]))
    end

    def func_section : Bytes
      WASM_Emitter.createSection(Section::Func, WASM_Emitter.encodeVector([Bytes[1]]))
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

    def export_section : Bytes
      WASM_Emitter.createSection(Section::Export,
        WASM_Emitter.encodeVector([
          WASM_Emitter.encodeString("run") + Bytes[ExportType::Func.value] + WASM_Emitter.unsignedLEB128(RUN_FUNC_INDEX),
        ]))
    end

    # Emit code that leaves the value of expression node `i` on the stack.
    def expression(i : Int32) : Bytes
      n = @program[i]
      case n.rule
      when :lex
        n.type == Type::Identifier ? global_get(@program.value(n)) : const(@program.value(n).to_i32)
      when :assign
        name = @program.value(@program.arg(i, 0))
        expression(@program.arg(i, 2)) + global_set(name) + global_get(name)
      when :paren
        expression(@program.arg(i, 1))
      when :neg
        const(0) + expression(@program.arg(i, 1)) + op(Opcodes::I32_sub)
      when :mul, :add, :cmp, :eq
        binary(@program.type(@program.arg(i, 1)), expression(@program.arg(i, 0)), expression(@program.arg(i, 2)))
      when :command1
        expression(@program.arg(i, 1)) + call(PUTS_IMPORT_INDEX)
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
      else
        raise Unsupported.new("operator #{opt} is not supported in WASM")
      end
    end

    # Statements a `while`/`until` body or `run` can contain.
    private def body_of(block : Int32) : Array(Int32)
      @program.children(block).select { |i| @program.type(i) == Type::Statement }
    end

    def statement(stmt : Int32, ctx : Ctx) : Bytes
      case @program[stmt].rule
      when :global
        expression(@program.arg(stmt, 4)) + global_set(@program.value(@program.arg(stmt, 2)))
      when :while
        loop_statement(stmt, ctx, while_true: true)
      when :until
        loop_statement(stmt, ctx, while_true: false)
      when :break
        exit = ctx.loops.last? || raise Unsupported.new("break outside of a loop")
        op(Opcodes::Br) + WASM_Emitter.unsignedLEB128(ctx.depth - exit)
      when :if
        if_statement(stmt, ctx)
      else
        expression(@program.arg(stmt, 0)) + op(Opcodes::Drop)
      end
    end

    # `while`/`until`: `block { loop { cond; br_if exit; body; br loop } }`.
    # `while` exits when the condition is false (`i32.eqz` first); `until`
    # exits when it is true.
    private def loop_statement(stmt : Int32, ctx : Ctx, while_true : Bool) : Bytes
      head = @program.children(stmt)[0]
      cond = @program.arg(head, 1)
      code = op(Opcodes::Block) + Bytes[BlockVoid]
      ctx.depth += 1
      exit = ctx.depth
      ctx.loops << exit
      code += op(Opcodes::Loop) + Bytes[BlockVoid]
      ctx.depth += 1
      code += expression(cond)
      code += op(Opcodes::I32_eqz) if while_true
      code += op(Opcodes::Br_if) + WASM_Emitter.unsignedLEB128(ctx.depth - exit)
      body_of(stmt).each { |s| code += statement(s, ctx) }
      code += op(Opcodes::Br) + WASM_Emitter.unsignedLEB128(0)
      ctx.depth -= 1
      code += op(Opcodes::End) # loop
      ctx.loops.pop
      ctx.depth -= 1
      code += op(Opcodes::End) # block
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
      code = expression(cond) + op(Opcodes::If) + Bytes[BlockVoid]
      ctx.depth += 1
      code = stmts.reduce(code) { |c, s| c + statement(s, ctx) }
      rest = branches[1..]
      unless rest.empty?
        code += op(Opcodes::Else) + emit_branches(rest, ctx)
      end
      ctx.depth -= 1
      code + op(Opcodes::End)
    end

    # `run`: one `statement` per top-level statement.
    def code_section : Bytes
      ctx = Ctx.new
      code = Bytes[]
      body_of(@program.root).each { |stmt| code += statement(stmt, ctx) }
      code += op(Opcodes::End)
      body = Bytes[0] + code # no locals
      WASM_Emitter.createSection(Section::Code,
        WASM_Emitter.encodeVector([WASM_Emitter.unsignedLEB128(body.size) + body]))
    end

    def to_wasm : Bytes
      WASM_Emitter.minimal_module + type_section + import_section + func_section +
        global_section + export_section + code_section
    end
  end
end
