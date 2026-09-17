require "./wasm_emitter"

# A debugging aid, not a general WASM tool: decodes exactly the shapes
# `WASM_Emitter` itself produces back into readable text, one line per
# instruction, so a compiled module can be inspected without a separate
# `wasm2wat` on the machine. Reads its own encoding (LEB128, the section
# layout, the opcode set `WASM_Emitter::Opcodes` already names) in
# reverse.
module CrystalRobots::Compiler
  class Disassembler
    private class Reader
      def initialize(@bytes : Bytes, @pos : Int32 = 0)
      end

      def eof? : Bool
        @pos >= @bytes.size
      end

      def byte : UInt8
        b = @bytes[@pos]
        @pos += 1
        b
      end

      def bytes(n : Int32) : Bytes
        slice = @bytes[@pos, n]
        @pos += n
        slice
      end

      def unsignedLEB128 : Int32
        result = 0
        shift = 0
        loop do
          b = byte
          result |= (b & 0x7f).to_i32 << shift
          break if b & 0x80 == 0
          shift += 7
        end
        result
      end

      def signedLEB128 : Int32
        result = 0
        shift = 0
        b = 0_u8
        loop do
          b = byte
          result |= (b & 0x7f).to_i32 << shift
          shift += 7
          break if b & 0x80 == 0
        end
        result |= (~0 << shift) if shift < 32 && (b & 0x40) != 0
        result
      end

      def string(n : Int32) : String
        String.new(bytes(n))
      end
    end

    # Operand shape for each opcode this emitter ever produces.
    OPERANDS = {
      WASM_Emitter::Opcodes::Block      => :blocktype,
      WASM_Emitter::Opcodes::Loop       => :blocktype,
      WASM_Emitter::Opcodes::If         => :blocktype,
      WASM_Emitter::Opcodes::Br         => :u32,
      WASM_Emitter::Opcodes::Br_if      => :u32,
      WASM_Emitter::Opcodes::Call       => :u32,
      WASM_Emitter::Opcodes::Local_get  => :u32,
      WASM_Emitter::Opcodes::Local_set  => :u32,
      WASM_Emitter::Opcodes::Local_tee  => :u32,
      WASM_Emitter::Opcodes::Global_get => :u32,
      WASM_Emitter::Opcodes::Global_set => :u32,
      WASM_Emitter::Opcodes::I32_const  => :i32,
    }

    def self.disassemble(wasm : Bytes) : String
      String.build { |io| new(wasm).print(io) }
    end

    def initialize(@wasm : Bytes)
    end

    def print(io : IO) : Nil
      r = Reader.new(@wasm, 8) # skip the 8-byte header, already checked by the parser
      while !r.eof?
        id = r.byte
        size = r.unsignedLEB128
        body = Reader.new(r.bytes(size))
        case id
        when WASM_Emitter::Section::Import.value
          print_imports(io, body)
        when WASM_Emitter::Section::Global.value
          io << (body.unsignedLEB128) << " mutable i32 global(s), initialized to 0\n"
        when WASM_Emitter::Section::Export.value
          print_exports(io, body)
        when WASM_Emitter::Section::Code.value
          print_code(io, body)
        end
      end
    end

    private def print_imports(io : IO, r : Reader) : Nil
      count = r.unsignedLEB128
      count.times do
        mod = r.string(r.unsignedLEB128)
        name = r.string(r.unsignedLEB128)
        r.byte # export kind, always func here
        type = r.unsignedLEB128
        io << "import " << mod << '.' << name << " (type " << type << ")\n"
      end
    end

    private def print_exports(io : IO, r : Reader) : Nil
      count = r.unsignedLEB128
      count.times do
        name = r.string(r.unsignedLEB128)
        r.byte # export kind
        index = r.unsignedLEB128
        io << "export " << name << " -> func " << index << '\n'
      end
    end

    private def print_code(io : IO, r : Reader) : Nil
      count = r.unsignedLEB128
      count.times do |i|
        size = r.unsignedLEB128
        body = Reader.new(r.bytes(size))
        io << "func " << i << ":\n"
        local_groups = body.unsignedLEB128
        local_groups.times do
          n = body.unsignedLEB128
          body.byte # valtype, always i32
          io << "  (local i32) x" << n << '\n' if n > 0
        end
        print_instructions(io, body, indent: 2)
      end
    end

    private def print_instructions(io : IO, r : Reader, indent : Int32) : Nil
      pad = " " * indent
      until r.eof?
        code = r.byte
        op = WASM_Emitter::Opcodes.from_value?(code)
        unless op
          io << pad << "0x" << code.to_s(16) << '\n'
          next
        end
        io << pad << op.to_s.downcase
        case OPERANDS[op]?
        when :u32       then io << ' ' << r.unsignedLEB128
        when :i32       then io << ' ' << r.signedLEB128
        when :blocktype then r.byte # always the void blocktype
        end
        io << '\n'
      end
    end
  end
end
