module CrystalRobots
  class Compiler
    def tokenizer(input)
    end

    def uLEB128(n)
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

    def emitter
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
      enum Types
        i32 = 0x7f
        f32 = 0x7d
      end

      # https://webassembly.github.io/spec/core/binary/instructions.html
      enum Opcodes
        end = 0x0b
        get_local = 0x20
        f32_add = 0x92
      end

      # http://webassembly.github.io/spec/core/binary/modules.html#export-section
      enum ExportType
        func = 0x00
        table = 0x01
        mem = 0x02
        global = 0x03
      end

      # http://webassembly.github.io/spec/core/binary/types.html#function-types
      functionType = 0x60

      emptyArray = 0

      # https://webassembly.github.io/spec/core/binary/modules.html#binary-module
      magicModuleHeader = Bytes[0,'a'.ord,'s'.ord,'m'.ord]
      moduleVersion = Bytes[1,0,0,0]

      # https://webassembly.github.io/spec/core/binary/conventions.html#binary-vec
      # Vectors are encoded with their length followed by their element sequence
      def encodeVector(data)
        uLEB128(data.length) +
        Bytes[data]
      end

      def createSection(type, data)
        type +
        encodeVector(data)
      end

      magicModuleHeader +
      moduleVersion +
      0
    end
  end
end

c = CrystalRobots::Compiler.new
puts c.emitter
