require "./program"
require "./parser"

# The WebAssembly emitter. Every module starts with the same 8 bytes: a
# 4-byte magic number spelling `\0asm` and a 4-byte version, followed by
# sections, each a section id byte, the section's byte length, and its own
# vector of entries.
#
# `WASM_Emitter.new(program).to_wasm` walks the AST that `Parser` built.
# The module it produces imports `env.puts` and exports `run`, which calls
# it once per top-level statement; this commit adds parenthesized, unary
# minus and binary arithmetic expressions as things `puts` can be called
# with, alongside a bare number literal.
#
# https://webassembly.github.io/spec/core/binary/modules.html
module CrystalRobots::Compiler
  class WASM_Emitter
    # https://webassembly.github.io/spec/core/binary/modules.html#sections
    enum Section : UInt8
      Type   =  1
      Import =  2
      Func   =  3
      Export =  7
      Code   = 10
    end

    # https://webassembly.github.io/spec/core/binary/types.html
    enum Valtype : UInt8
      I32 = 0x7f
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes : UInt8
      End       = 0x0b
      Call      = 0x10
      Drop      = 0x1a
      I32_const = 0x41
      I32_add   = 0x6a
      I32_sub   = 0x6b
      I32_mul   = 0x6c
      I32_div_s = 0x6d
      I32_rem_s = 0x6f
    end

    class Unsupported < Exception
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
        const(@program.value(n).to_i32)
      when :paren
        expression(@program.arg(i, 1))
      when :neg
        const(0) + expression(@program.arg(i, 1)) + op(Opcodes::I32_sub)
      when :mul, :add
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
      else
        raise Unsupported.new("operator #{opt} is not supported in WASM")
      end
    end

    # `run`: one `expression; drop` per top-level statement.
    def code_section : Bytes
      code = Bytes[]
      @program.children(@program.root).each do |stmt|
        code += expression(@program.arg(stmt, 0)) + op(Opcodes::Drop)
      end
      code += op(Opcodes::End)
      body = Bytes[0] + code # no locals
      WASM_Emitter.createSection(Section::Code,
        WASM_Emitter.encodeVector([WASM_Emitter.unsignedLEB128(body.size) + body]))
    end

    def to_wasm : Bytes
      WASM_Emitter.minimal_module + type_section + import_section + func_section + export_section + code_section
    end
  end
end
