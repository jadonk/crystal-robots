# The WebAssembly emitter. Every module starts with the same 8 bytes: a
# 4-byte magic number spelling `\0asm` and a 4-byte version. A real module
# adds sections after that, each one a section id byte followed by the
# section's byte length and its own vector of entries.
#
# https://webassembly.github.io/spec/core/binary/modules.html
module CrystalRobots::Compiler
  class WASM_Emitter
    # https://webassembly.github.io/spec/core/binary/modules.html#sections
    enum Section : UInt8
      Type   =  1
      Func   =  3
      Export =  7
      Code   = 10
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes : UInt8
      End       = 0x0b
      Local_get = 0x20
      I32_add   = 0x6a
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

    def self.encodeVector(entries : Array(Bytes)) : Bytes
      unsignedLEB128(entries.size) + entries.reduce(Bytes[]) { |a, b| a + b }
    end

    def self.encodeString(string : String) : Bytes
      unsignedLEB128(string.bytesize) + string.to_slice
    end

    def self.createSection(type : Section, data : Bytes) : Bytes
      Bytes[type.value] + unsignedLEB128(data.size) + data
    end

    # One function, `(i32, i32) -> i32`, exported as `add`, that adds its
    # two parameters. Hand-assembled: there is no compiler yet, only the
    # binary encoding rules a compiler will eventually target.
    def self.add_module : Bytes
      type_section = createSection(Section::Type,
        encodeVector([Bytes[FunctionType, 2, 0x7f, 0x7f, 1, 0x7f]])) # (i32, i32) -> i32
      func_section = createSection(Section::Func, encodeVector([Bytes[0]]))
      export_section = createSection(Section::Export,
        encodeVector([encodeString("add") + Bytes[0x00, 0]])) # func export, function index 0
      body = Bytes[0] +                                       # no locals beyond the parameters
             Bytes[Opcodes::Local_get.value, 0] +
             Bytes[Opcodes::Local_get.value, 1] +
             Bytes[Opcodes::I32_add.value] +
             Bytes[Opcodes::End.value]
      code_section = createSection(Section::Code, encodeVector([unsignedLEB128(body.size) + body]))
      minimal_module + type_section + func_section + export_section + code_section
    end
  end
end
