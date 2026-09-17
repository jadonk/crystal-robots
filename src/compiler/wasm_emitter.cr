# The WebAssembly emitter. Every module starts with the same 8 bytes: a
# 4-byte magic number spelling `\0asm` and a 4-byte version. Nothing else
# is required for a module to be valid — it just has no imports, functions
# or exports.
#
# https://webassembly.github.io/spec/core/binary/modules.html#binary-module
module CrystalRobots::Compiler
  class WASM_Emitter
    MagicModuleHeader = Bytes[0x00, 'a'.ord, 's'.ord, 'm'.ord]
    ModuleVersion     = Bytes[0x01, 0x00, 0x00, 0x00]

    def self.minimal_module : Bytes
      MagicModuleHeader + ModuleVersion
    end
  end
end
