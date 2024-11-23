# TODO: Write documentation for `CrystalRobots::Compiler::WASM_Emitter`

module CrystalRobots::Compiler
  class WASM_Emitter
    @code : Bytes

    def initialize(ast : Program)
      @program = ast
      @code = Bytes[]
    end

    # https://en.wikipedia.org/wiki/LEB128
    def unsignedLEB128(n : UInt32 | Int32) : Bytes
      buffer = Bytes[]
      loop do
        byte = n & 0x7f
        n = n >> 7
        if n != 0
          byte |= 0x80
        end
        buffer += Bytes[byte]
        if n == 0
          break
        end
      end
      buffer
    end

    def signedLEB128(n : Int32) : Bytes
      buffer = Bytes[]
      more = true
      isNegative = n.negative?
      bitCount = n.bit_length
      while more
        byte = n & 0x7f
        n = n >> 7
        if isNegative
          n = n | -(1 << (bitCount - 8))
        end
        if (n == 0 && (byte & 0x40) == 0) || (n == -1 && (byte & 0x40) != 0x40)
          more = false
        else
          byte = byte | 0x80
        end
        buffer += Bytes[byte]
      end
      buffer
    end

    # https://webassembly.github.io/spec/core/binary/conventions.html#binary-vec
    # Vectors are encoded with their length followed by their element sequence
    def encodeVector(data : Bytes) : Bytes
      unsignedLEB128(data.size) +
        data
    end

    # https://webassembly.github.io/spec/core/binary/values.html#names
    def encodeString(string : String) : Bytes
      unsignedLEB128(string.bytesize) +
        string.encode("UTF-8")
    end

    # https://webassembly.github.io/spec/core/binary/modules.html#sections
    enum Section : UInt8
      Custom  =  0
      Type    =  1
      Import  =  2
      Func    =  3
      Table   =  4
      Memory  =  5
      Global  =  6
      Export  =  7
      Start   =  8
      Element =  9
      Code    = 10
      Data    = 11
    end

    # https://webassembly.github.io/spec/core/binary/types.html
    enum Valtype : UInt8
      Externref = 0x6f
      Funcref   = 0x70
      V128      = 0x7b
      F64       = 0x7c
      F32       = 0x7d
      I64       = 0x7e
      I32       = 0x7f
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes : UInt8
      End       = 0x0b
      Call      = 0x10
      Drop      = 0x1a
      Get_local = 0x20
      I32_const = 0x41 # constants
      F32_const = 0x43
      I32_eqz   = 0x45 # I32 compare
      I32_eq    = 0x46
      I32_neq   = 0x47
      I32_lt_s  = 0x48
      I32_lt_u  = 0x49
      I32_gt_s  = 0x4a
      I32_gt_u  = 0x4b
      I32_le_s  = 0x4c
      I32_le_u  = 0x4d
      I32_ge_s  = 0x4e
      I32_ge_u  = 0x4f
      F32_eq    = 0x5b # F32 compare
      F32_ne    = 0x5c
      F32_lt    = 0x5d
      F32_gt    = 0x5e
      F32_le    = 0x5f
      F32_ge    = 0x60
      I32_add   = 0x6a # I32 arithmatic
      I32_sub   = 0x6b
      I32_mul   = 0x6c
      I32_div_s = 0x6d
      I32_div_u = 0x63
      I32_and   = 0x71
      I32_or    = 0x72
      I32_xor   = 0x73
      I32_shl   = 0x74
      I32_shr_s = 0x75
      I32_shr_u = 0x76
      F32_add   = 0x92 # F32 arithmatic
      F32_sub   = 0x93
      F32_mul   = 0x94
      F32_div   = 0x95
    end

    # http://webassembly.github.io/spec/core/binary/modules.html#export-section
    enum ExportType : UInt8
      Func   = 0x00
      Table  = 0x01
      Mem    = 0x02
      Global = 0x03
    end

    # http://webassembly.github.io/spec/core/binary/types.html#function-types
    FunctionType = 0x60

    # https://webassembly.github.io/spec/core/binary/modules.html#binary-module
    MagicModuleHeader = Bytes[0, 'a'.ord, 's'.ord, 'm'.ord]
    ModuleVersion     = Bytes[1, 0, 0, 0]

    def createSection(type : Section, data : Bytes)
      Bytes[type.value] +
        encodeVector(data)
    end

    # Function types are vectors of parameters and return types. Currently
    # WebAssembly only supports single return values
    # the type section is a vector of function types
    def typeSection
      createSection(Section::Type,
        Bytes[4] +                                                          # num types = 4
        Bytes[FunctionType, 0, 0] +                                         # func type 0, 0 params, 0 results
        Bytes[FunctionType, 0, 1, Valtype::I32] +                           # func type 0, 0 params, 1 result (i32)
        Bytes[FunctionType, 1, Valtype::I32, 1, Valtype::I32] +             # func type 1, 1 params (i32), 1 result (i32)
        Bytes[FunctionType, 2, Valtype::I32, Valtype::I32, 1, Valtype::I32] # func type 2, 2 params (i32, i32), 1 result (i32)
      )
    end

    def importSection
      createSection(Section::Import,
        Bytes[1] +                      # num imports = 1
        encodeString("env") +           # import module name = "env"
        encodeString("puts") +          # import field name = "puts"
        Bytes[ExportType::Func.value] + # import kind = Func
        Bytes[2]                        # import signature index = 2
      )
    end

    # the function section is a vector of type indices that indicate the type of each function
    # in the code section
    def funcSection
      createSection(Section::Func,
        Bytes[1] + # num functions = 1
        Bytes[1]   # function 0 signature index = 1
      )
    end

    # the export section is a vector of exported functions
    def exportSection
      createSection(Section::Export,
        Bytes[1] +                      # num exports = 1
        encodeString("run") +           # export name = "run"
        Bytes[ExportType::Func.value] + # export type = Func
        Bytes[1]                        # export func index = 1
      )
    end

    def codeFromAst(ast : Program)
      code = Bytes[0] # local decl count = 0
      Range.new(0, ast.ast.size, exclusive = true).reverse_each do |i|
        ast.ast[i].each_index do |j|
          p = ast.ast[i][j].type
          case p
          when Type::OneArgStatement
            a = ast.ast[i][j].index + 1
            t = ast.ast[i - 1][a]
            case t.type
            when Type::Number
              code += Bytes[Opcodes::I32_const.value]
              code += signedLEB128(t.value.to_i32)
            else
              raise "Unsupported argument type: #{t.type} at #{a}"
            end
            code += Bytes[Opcodes::Call.value]
            code += unsignedLEB128(0)
          end
        end
      end
      code += Bytes[Opcodes::End]
      code
    end

    # the code section contains vectors of functions
    # https://webassembly.github.io/spec/core/binary/modules.html#binary-codesec
    def codeSection(ast : Program)
      createSection(Section::Code,
        Bytes[1] + # num functions = 1
        encodeVector(codeFromAst(ast))
      )
    end

    # Helpful tool for exploring - https://webassembly.github.io/wabt/demo/wat2wasm/
    def to_wasm
      ast = @program
      MagicModuleHeader +
        ModuleVersion +
        typeSection +
        importSection +
        funcSection +
        exportSection +
        codeSection(ast)
    end
  end
end
