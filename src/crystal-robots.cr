# TODO: Write documentation for `CrystalRobots`
require "option_parser"
require "math"
require "random"
require "fiber"

module CrystalRobots
  VERSION = "0.0.1"

  # Robot intrinsic functions
  #
  # http://tpoindex.github.io/crobots/docs/crobots_manual.html#8
  #
  # This is to enable native compilation of robots for syntax checking
  #
  # I'm trying to figure out how to interrupt the robot flow at some
  # interval. It will never match the WASM interpreter cycles, but I
  # hope I can make each robot yield to let another robot run.
  #
  class Robot
    @@num_robots = 0
    @@robots = [] of Robot
    MAX_CALLS     = 100
    MAXROBOTS     =   4 # maximum number of robots
    MOTION_CYCLES =  15 # number of cycles before motion update
    ROBOT_SPEED   =   7 # multiplicative speed factor
    TURN_SPEED    =  50 # maximum speed for direction change
    ACCEL         =  10 # acceleration per motion cycle
    @i : Int32

    def initialize(name : String)
      @name = "#{name}"
      @status = 0
      @calls = 0
      @x = 0
      @y = 0
      @org_x = 0
      @org_y = 0
      @range = 0
      @last_x = -1
      @last_y = -1
      @speed = 0
      @last_speed = -1
      @accel = 0
      @d_speed = 0
      @damage = 0
      @last_damage = -1
      @scan = 0
      @last_scan = -1
      @reload = 0
      @i = @@num_robots
      @@num_robots += 1
      if @@num_robots > MAXROBOTS
        raise "Too many robots!"
      end
    end

    def main(&program : Robot -> Nil)
      @@robots << self
      @program = program
      run
    end

    def run
      if program = @program
        puts "Running robot #{@i}, aka '#{@name}'"
        begin
          program.call(self)
        rescue ex
          puts "Stopping robot #{@i}, aka #{@name}: #{ex.message}"
        end
      end
    end

    def debug(s)
      @calls += 1
      puts "#{@calls}: #{s}"
      if @calls >= MAX_CALLS
        raise "Maximum number of calls reached"
      end
    end

    def scan(degree, resolution)
      debug "scan #{degree} #{resolution}"
      0
    end

    def cannon(degree, range)
      r = true
      debug "cannon #{degree} #{range} -> #{r}"
      r
    end

    def drive(degree, speed)
      debug "drive #{degree} #{speed}"
    end

    def damage
      debug "damage -> #{@damage}"
      @damage
    end

    def speed
      debug "speed -> #{speed}"
      @speed
    end

    def loc_x
      r = @x // 100
      debug "loc_x -> #{r}"
      r
    end

    def loc_y
      r = @y // 100
      debug "loc_y -> #{r}"
      r
    end
  end

  class Missile
    MIS_SPEED = 500 # how far in one motion cycle (in clicks)
    MIS_RANGE = 700 # maximum missile range
    MIS_ROBOT =   2 # number of active missiles per robot
    AVAIL     =   0 # missile available for use
    FLYING    =   1 # missile in air
    EXPLODING =   2 # missile exploding on ground
    RELOAD    =  15 # motion cycles before reload
    EXP_COUNT =   5 # motion cycles for exploding missile

    def initialize
      @stat = AVAIL  # missile status
      @beg_x = 0     # beginning x * 100
      @beg_y = 0     # beginning y * 100
      @cur_x = 0     # current x * 100
      @cur_y = 0     # current y * 100
      @last_xx = -1  # last plotted x
      @last_yy = -1  # last plotted y
      @head = 0      # heading, 0 - 359
      @count = 0     # cycle count for exploding missiles
      @rang = 0      # range of missile
      @curr_dist = 0 # current distance from origin * 100
    end
  end

  # Crystal Robots compiler
  #
  # ## Description
  #
  # The Crystal Robots compiler accepts a limited subset of the [Crystal Programming Language](https://crystal-lang.org). The entire program must be a single source file. No macro operations are supported. The compile machine code targets [WebAssembly](https://webassembly.org/) and calls various functions in a browser-based simulation
  #
  # ## Features missing
  #
  class Compiler
    @code : Bytes

    def initialize
      @code = Bytes[]
    end

    enum TokenType
      Number
      Keyword
      Whitespace
    end

    struct Token
      property type, value

      def initialize(@type : TokenType, @value : String)
      end
    end

    def regexMatcher(regex : String, type : TokenType)
    end

    @@keywords = [
      "begin",
      "break",
      "case",
      "def",
      "do",
      "else",
      "elsif",
      "end",
      "false",
      "for",
      "if",
      "in",
      "next",
      "nil",
      "require",
      "then",
      "true",
      "while",
    ].join("|")

    @@matchers = [
      {/^([.0-9]+)/, TokenType::Number},
      {Regex.new("^(#{@@keywords})"), TokenType::Keyword},
      {/^(\s+)/, TokenType::Whitespace},
    ]

    class TokenizerError < Exception
    end

    def tokenizer(src : String)
      tokens = Array(Token).new
      index = 0
      while index < src.size
        matches = @@matchers.compact_map do |regex, type|
          m = regex.match(src[(index..)])
          if m.nil?
            next
          end
          {"m": m, "type": type}
        end
        if matches.size == 0
          raise TokenizerError.new("Unexpected token #{src[index..index + 1]}")
        end
        if !matches[0].nil? && !matches[0][:m][0].nil?
          # puts "Found #{matches[0][:m][0]} as #{matches[0][:type]}"
          if matches[0][:type] != TokenType::Whitespace
            t = Token.new(type: matches[0][:type], value: matches[0][:m][0])
            tokens << t
          end
          index += matches[0][:m][0].size
        else
          raise TokenizerError.new("Unexpected match in token array #{src[index..index + 1]}")
        end
      end
      tokens
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
      F32_const = 0x43
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
        Bytes[0]   # type index
      )
    end

    # the export section is a vector of exported functions
    def exportSection
      createSection(Section::Export,
        Bytes[1] + # number of exports
        encodeString("run") +
        Bytes[ExportType::Func.value] + # export type
        Bytes[0x00]                     # function index
      )
    end

    def emitExpression(node : ExpressionNode)
      case node.type
      when "numberLiteral"
        @code << Bytes[Opcodes::F32_const.local]
        @code << ieee754(node.value)
      end
    end

    # def codeFromAst(ast : Program)
    def code
      Bytes[0] + # number of locals
        Bytes[Opcodes::Get_local.value] +
        Bytes[0] + # index 0
        Bytes[Opcodes::Get_local.value] +
        Bytes[1] + # index 1
        Bytes[Opcodes::F32_add.value] +
        Bytes[Opcodes::End.value]
    end

    # the code section contains vectors of functions
    # def codeSection(ast : Program)
    def codeSection
      createSection(Section::Code,
        Bytes[1] + # number of functions
        # encodeVector(codeFromAst(ast : Program))
        encodeVector(code)
      )
    end

    # Helpful tool for exploring - https://webassembly.github.io/wabt/demo/wat2wasm/
    # def emitter(ast : Program)
    def emitter
      MagicModuleHeader +
        ModuleVersion +
        typeSection +
        funcSection +
        exportSection +
        # codeSection(ast)
        codeSection
    end
  end

  class Battlefield
  end

  class CLI
    @robot : String | Nil
    @robots : Array(String) | Nil

    def initialize
      @matches = 1
      @cycles = 500_000

      # TODO: http://tpoindex.github.io/crobots/docs/crobots_manual.html#4
      parser = OptionParser.new
      customize_parser(parser)
      parser.parse

      if @robots.nil?
        puts parser
        1
      end
    end

    def customize_parser(parser)
      parser.banner = "Welcome to Crystal Robots!\nUsage: crystal-robots [options] robot-source-file-1 [robot-source-file-n] [>file]"
      parser.on "-v", "--version", "Show version" do
        puts CrystalRobots::VERSION
        parser.stop
      end
      parser.on "-h", "--help", "Show help" do
        puts parser
        parser.stop
      end
      parser.on "-c ROBOT", "--compile=ROBOT", "Compile robot source only and output WebAssembly (WASM)" do |robot|
        # TODO: call the compiler and output .WASM with symbol tables
        STDERR.puts "Compiling #{robot}"
        @robot = robot
      end
      parser.on "-m MATCHES", "--matches=MATCHES", "Run MATCHES matches" do |matches|
        # TODO: run the battlefield simulator repeatedly
        puts "Running #{matches} matches"
        @matches = matches.to_i32
      end
      parser.on "-l CYCLES", "--limit=CYCLES", "Set virtual machine cycle limit to CYCLES. Default is 500,000." do |cycles|
        # TODO: count cycles and enable setting the limit
        puts "Limiting virtual machine cycles to #{cycles}"
        @cycles = cycles.to_i32
      end
      parser.unknown_args do |args, _|
        if args.size > 0
          robots = args
          puts "Running with robots: #{robots}"
          @robots = robots
        end
      end
    end
  end
end

def rand(limit)
  r = Random.rand(limit)
  puts "rand #{limit} -> #{r}"
  r
end

def sqrt(number)
  r = Math.isqrt(number.abs)
  puts "sqrt #{number} -> #{r}"
  r
end

def sin(degree)
  r = f2i(Math.sin(d2r(degree)))
  puts "sin #{degree} -> #{r}"
  r
end

def cos(degree)
  r = f2i(Math.cos(d2r(degree)))
  puts "cos #{degree} -> #{r}"
  r
end

def tan(degree)
  r = f2i(Math.tan(d2r(degree)))
  puts "tan #{degree} -> #{r}"
  r
end

def atan(ratio)
  r = r2d(Math.atan(i2f(ratio)))
  puts "tan #{ratio} -> #{r}"
  r
end

private def d2r(degree)
  degree * Math::PI / 180
end

private def r2d(radian)
  (radian * 180 / Math::PI).to_i32
end

private def f2i(x)
  (x*100000).to_i32
end

private def i2f(n)
  (n/100000).to_f32
end

CrystalRobots::CLI.new
