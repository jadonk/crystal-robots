module CrystalRobots
  class Tokenizer
    def tokenizer(input)
    end
  end

  class Emitter
    # https://webassembly.github.io/spec/core/binary/modules.html#binary-module
    MagicModuleHeader = Bytes[0,'a'.ord,'s'.ord,'m'.ord]
    ModuleVersion = Bytes[1,0,0,0]

    def emitter
      MagicModuleHeader +
      ModuleVersion
    end
  end
end
