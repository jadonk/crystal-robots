module CrystalRobots
  class Compiler
    def tokenizer(input)
    end

    def emitter
      # https://webassembly.github.io/spec/core/binary/modules.html#binary-module
      magicModuleHeader = Bytes[0,'a'.ord,'s'.ord,'m'.ord]
      moduleVersion = Bytes[1,0,0,0]

      magicModuleHeader +
      moduleVersion +
      0
    end
  end
end

c = CrystalRobots::Compiler.new
puts c.emitter
