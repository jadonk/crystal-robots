# TODO: Write documentation for `CrystalRobots`
require "./compiler"
require "option_parser"
require "wait_group"

ENV["DEBUG"] ||= "0"

module CrystalRobots
  VERSION = "0.0.1"

  class Log
    @@loglevel = ENV["DEBUG"]

    def self.d(s)
      if @@loglevel.to_i > 0
        puts s
      end
    end
  end

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
    @@active_robot : Robot | Nil

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

    def self.active_robot
      @@active_robot
    end

    def self.num_robots
      @@num_robots
    end

    def self.robots
      @@robots
    end

    def activate
      @@active_robot = self
    end

    def name
      @name
    end

    def main(&program : Robot -> Nil)
      @@robots << self
      @program = program
    end

    def run
      if !@program.nil?
        puts "Starting robot '#{@name}.#{@i}'"
        begin
          p = @program.not_nil!
          p.call(self)
        rescue ex
          puts "Stopping robot '#{@name}.#{@i}' : #{ex.message}"
        end
      end
    end

    def debug(s)
      sleep 0.second
      self.activate
      @calls += 1
      puts "#{@calls}: #{@name}.#{@i} #{s}"
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
      debug "speed -> #{@speed}"
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

    def sleep
      debug "sleep"
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

  class Battlefield
  end

  class CLI
    @robot_to_compile : String | Nil
    @robots_to_battle : Array(String) | Nil
    @port : UInt32 | Nil
    @outfile : String | Nil

    def initialize(@run_parser = true, @matches = 1, @cycles = 500_000, @exit = false, @interpreter = false, @robot_to_compile = nil, @robots_to_battle = nil, @port = nil, @outfile = nil)
    end

    def run
      if @run_parser
        # TODO: http://tpoindex.github.io/crobots/docs/crobots_manual.html#4
        parser = OptionParser.new
        customize_parser(parser)
        parser.parse
      end

      if @exit
        return 0
      end

      if !@robot_to_compile.nil?
        STDERR.puts "Compiling #{@robot_to_compile}"
        source = File.read("#{@robot_to_compile}")
        program = Compiler::Program.new(source)
        Compiler::Parser.new(program)
        binfile = Compiler::WASM_Emitter.new(program).to_wasm
        if @outfile.nil?
          STDOUT.write(binfile)
        else
          File.write("#{@outfile}", binfile)
        end
        return 0
      end

      if @robots_to_battle.nil?
        if Robot.num_robots > 0 # there may be already compiled robots
          already_compiled_robots = [] of String
          Robot.robots.not_nil!
          Robot.robots.each do |robot|
            name = robot.name
            name.not_nil!
            already_compiled_robots << robot.name
          end
          @robots_to_battle = already_compiled_robots
        else
          puts parser
          return 1
        end
      end

      if @robots_to_battle.not_nil!.size > 4
        puts "Maximum of 4 robots allowed"
        return 1
      end

      # TODO: Call for battle
      puts "Start by running each of #{@robots_to_battle}"
      Robot.robots.not_nil!
      WaitGroup.wait do |wg|
        Robot.robots.each do |robot|
          wg.spawn do
            puts "Running #{robot.name}"
            robot.run
          end
        end
      end
    end

    def customize_parser(parser)
      parser.banner = "Welcome to Crystal Robots!\nUsage: crystal-robots [options] robot-source-file-1 [..2 [..3 [robot-source-file-4]]] [>file]"
      parser.on "-v", "--version", "Show version" do
        puts CrystalRobots::VERSION
        @exit = true
        parser.stop
      end
      parser.on "-h", "--help", "Show help" do
        puts parser
        @exit = true
        parser.stop
      end
      parser.on "-i", "--interpret", "Run robots in interpreter" do
        @interpreter = true
      end
      parser.on "-c ROBOT", "--compile=ROBOT", "Compile robot source only and output WebAssembly (WASM)" do |robot|
        @robot_to_compile = robot
        parser.stop
      end
      parser.on "-o OUTFILE", "--output=OUTFILE", "Write compiled robot to OUTFILE" do |outfile|
        @outfile = outfile
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
      parser.on "-p PORT", "--port=PORT", "Serve web interface on port PORT" do |port|
        # TODO: implement web server
        puts "Serving Crystal Robots on port #{port}"
        @port = port.to_u32
        @exit = true
        parser.stop
      end
      parser.on "-s DIR", "--static=DIR", "Save static web interface files to DIR" do |dir|
        # TODO: implement web server
        puts "Writing static web interface files to #{dir}."
        @static_dir = "#{dir}"
        @exit = true
        parser.stop
      end
      parser.unknown_args do |args, _|
        if args.size > 0
          robots = args
          puts "Running with robots: #{robots}"
          @robots_to_battle = robots
        end
      end
    end

    def run_at_exit
      at_exit do
        run
      end
    end
  end
end
