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
      Get_local = 0x20
      I32_const = 0x41
      F32_const = 0x43
      I32_add   = 0x6a
      F32_add   = 0x92
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
    def int32Int32Type
      Bytes[FunctionType] +
        encodeVector(Bytes[Valtype::I32.value]) +
        encodeVector(Bytes[Valtype::I32.value])
    end

    def voidVoidType
      Bytes[FunctionType] +
        Bytes[0] +
        Bytes[0]
    end

    # the type section is a vector of function types
    def typeSection
      createSection(Section::Type,
        encodeVector(voidVoidType) +
        encodeVector(int32Int32Type)
      )
    end

    # the function section is a vector of type indices that indicate the type of each function
    # in the code section
    def funcSection
      createSection(Section::Func,
        Bytes[1] + # number of functions
        Bytes[0]   # type index
      )
    end

    def importSection
      createSection(Section::Import,
        encodeVector(
          encodeString("env") +
          encodeString("puts") +
          Bytes[ExportType::Func.value] +
          Bytes[0x01]
        )
      )
    end

    # the export section is a vector of exported functions
    def exportSection
      createSection(Section::Export,
        Bytes[1] + # number of exports
        encodeString("run") +
        Bytes[ExportType::Func.value] + # export type
        Bytes[0x01]                     # function index
      )
    end

    def codeFromAst(ast : Program)
      @code = Bytes[]
      ast.ast.each_index(start: -1, count: ast.ast.size) do |i|
        ast.ast[i].each_index do |j|
          case ast.ast[i][j].type
          when Tokenizer::Type::OneArgStatement
            a = ast.ast[i][j].index[1]
            t = ast.ast[i - 1][a]
            case t.type
            when Tokenizer::Type::Number
              @code += Bytes[Opcodes::I32_const.value]
              @code += signedLEB128(t.value.to_i32)
            else
              raise "Unsupported argument type"
            end
            @code += Bytes[Opcodes::Call.value]
            @code += unsignedLEB128(0)
          end
        end
      end
      @code
    end

    # the code section contains vectors of functions
    def codeSection(ast : Program)
      createSection(Section::Code,
        Bytes[1] + # number of functions
        encodeVector(codeFromAst(ast))
        Bytes[Opcodes::End]
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
