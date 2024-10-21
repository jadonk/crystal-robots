module CrystalRobots
  class Tokenizer
    def tokenizer(input)
    end
  end

  class Emitter
    def unsignedLEB128(n)
      buffer = Bytes.new()
      loop do
        byte = n & 0xff
        n = n >> 7
        if n != 0
          byte |= 0x80
        end
        buffer = buffer + Bytes[byte]
        if n == 0
          break
        end
      end
    end

    def encodeString(string)
      Bytes[string.size] +
      string.bytes
    end

    # https://webassembly.github.io/spec/core/binary/modules.html#sections
    enum Section
      Custom
      Type
      Import
      Func
      Table
      Memory
      Global
      Export
      Start
      Code
      Data
    end

    # https://webassembly.github.io/spec/core/binary/types.html
    enum Valtype
      I32 = 0x7f
      F32 = 0x7d
    end

    # https://webassembly.github.io/spec/core/binary/instructions.html
    enum Opcodes
      End = 0x0b
      Get_local = 0x20
      F32_add = 0x92
    end

    # http://webassembly.github.io/spec/core/binary/modules.html#export-section
    enum ExportType
      Func = 0x00
      Table = 0x01
      Mem = 0x02
      Global = 0x03
    end

    # http://webassembly.github.io/spec/core/binary/types.html#function-types
    FunctionType = Bytes[0x60]

    EmptyArray = 0

    # https://webassembly.github.io/spec/core/binary/modules.html#binary-module
    MagicModuleHeader = Bytes[0,'a'.ord,'s'.ord,'m'.ord]
    ModuleVersion = Bytes[1,0,0,0]

    # https://webassembly.github.io/spec/core/binary/conventions.html#binary-vec
    # Vectors are encoded with their length followed by their element sequence
    def encodeVector(data)
      unsignedLEB128(data.size) +
      Bytes[data]
    end

    def createSection(type, data)
      Bytes[type] +
      encodeVector(data)
    end

    # Function types are vectors of parameters and return types. Currently
    # WebAssembly only supports single return values
    def addFunctionType
      FunctionType +
      encodeVector([Valtype.F32, Valtype.F32]) +
      encodeVector([Valtype.F32])
    end

    # the type section is a vector of function types
    def typeSection
      Section.Type +
      encodeVector([addFunctionType])
    end

    # the function section is a vector of type indices that indicate the type of each function
    # in the code section
    def funcSection
      createSection(Section.Func, encodeVector([0x00])) # type index
    end

    # the export section is a vector of exported functions
    def exportSection
      createSection(Section.Export, encodeVector(
        [encodeString("run"), ExportType.Func, 0x00] # function index
      ))
    end

    # the code section contains vectors of functions
    def code
      [
        Opcodes.Get_local,
        unsignedLEB128(0),
        Opcodes.Get_local,
        unsignedLEB128(1),
        Opcodes.F32_add
      ]
    end

    def emitter
      MagicModuleHeader +
      ModuleVersion +
      0
    end
  end
end

