module CrystalRobots
  class TokenizerError < Exception
  end

  class Compiler
    @code : Bytes

    def initialize
      @code = Bytes[]
    end

    def tokenizer(src : String)
    end

    def parser(tokens)
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
        buffer = buffer + Bytes[byte]
        if n == 0
          break
        end
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
      Custom = 0
      Type = 1
      Import = 2
      Func = 3
      Table = 4
      Memory = 5
      Global = 6
      Export = 7
      Start = 8
      Element = 9
      Code = 10
      Data = 11
    end

    # https://webassembly.github.io/spec/core/binary/types.html
    enum Valtype : UInt8
      Externref = 0x6f
      Funcref = 0x70
      V128 = 0x7b
      F64 = 0x7c
      F32 = 0x7d
      I64 = 0x7e
      I32 = 0x7f
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes : UInt8
      End = 0x0b
      Call = 0x10
      Get_local = 0x20
      F32_const = 0x43
      F32_add = 0x92
    end

    # http://webassembly.github.io/spec/core/binary/modules.html#export-section
    enum ExportType : UInt8
      Func = 0x00
      Table = 0x01
      Mem = 0x02
      Global = 0x03
    end

    # http://webassembly.github.io/spec/core/binary/types.html#function-types
    FunctionType = 0x60

    # https://webassembly.github.io/spec/core/binary/modules.html#binary-module
    MagicModuleHeader = Bytes[0,'a'.ord,'s'.ord,'m'.ord]
    ModuleVersion = Bytes[1,0,0,0]

    def createSection(type : Section, data : Bytes)
      Bytes[type.value] +
      encodeVector(data)
    end

    # Function types are vectors of parameters and return types. Currently
    # WebAssembly only supports single return values
    def addFunctionType
      Bytes[FunctionType] +
      encodeVector(Bytes[Valtype::F32.value, Valtype::F32.value]) +
      encodeVector(Bytes[Valtype::F32.value])
    end

    # the type section is a vector of function types
    def typeSection
      createSection(Section::Type,
        Bytes[1] + # number of types
        addFunctionType()
      )
    end

    # the function section is a vector of type indices that indicate the type of each function
    # in the code section
    def funcSection
      createSection(Section::Func,
        Bytes[1] + # number of functions
        Bytes[0] # type index
      )
    end

    # the export section is a vector of exported functions
    def exportSection
      createSection(Section::Export,
        Bytes[1] + # number of exports
        encodeString("run") +
        Bytes[ExportType::Func.value] + # export type
        Bytes[0x00] # function index
      )
    end

    def emitExpression(node : ExpressionNode)
      case node.type
      when "numberLiteral"
        @code << Bytes[Opcodes::F32_const.local]
        @code << ieee754(node.value)
      end
    end

    def codeFromAst(ast : Program)
      Bytes[0] + # number of locals
      Bytes[Opcodes::Get_local.value] +
      Bytes[0] + # index 0
      Bytes[Opcodes::Get_local.value] +
      Bytes[1] + # index 1
      Bytes[Opcodes::F32_add.value] +
      Bytes[Opcodes::End.value]
    end

    # the code section contains vectors of functions
    def codeSection(ast : Program)
      createSection(Section::Code,
        Bytes[1] + # number of functions
        encodeVector(codeFromAst(ast : Program))
      )
    end

    # Helpful tool for exploring - https://webassembly.github.io/wabt/demo/wat2wasm/
    def emitter(ast : Program)
      MagicModuleHeader +
      ModuleVersion +
      typeSection +
      funcSection +
      exportSection +
      codeSection(ast)
    end
  end

  class Runtime
  end
end
