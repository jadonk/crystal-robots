# TODO: Write documentation for `CrystalRobots`
require "./compiler"
require "./battle/field"
require "option_parser"
require "wait_group"

ENV["DEBUG"] ||= "0"

module CrystalRobots
  VERSION = "0.0.1"

  # The Fossil check-in this binary was built from. Fossil's versioned
  # `manifest` setting (see .fossil-settings/manifest) keeps `manifest.uuid`
  # in every checkout and tarball; it is read at compile time. On the
  # GitHub mirror, `ci.cr` writes the equivalent git commit hash
  # there instead (see its "check manifest.uuid" step). "unknown" when
  # built from a plain source tree with neither.
  CHECKIN = {{ (read_file?("#{__DIR__}/../manifest.uuid") || "unknown").strip }}

  # Short check-in for display, like Fossil's own timeline.
  def self.checkin_short : String
    CHECKIN == "unknown" ? CHECKIN : CHECKIN[0, 10]
  end

  # "0.0.1 (check-in 724ff90d58)": what --version and /version report, so a
  # deploy can be compared with trunk.
  def self.version_line : String
    "crystal-robots #{VERSION} (check-in #{checkin_short})"
  end

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
    @robot_to_trace : String | Nil
    @ticks = false
    @robots_to_battle : Array(String) | Nil
    @port : UInt32 | Nil
    @outfile : String | Nil

    def initialize(@run_parser = true, @matches = 1, @cycles = 500_000, @seed = 1_u64, @exit = false, @interpreter = false, @robot_to_compile = nil, @robots_to_battle = nil, @port = nil, @outfile = nil)
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

      if (trace = @robot_to_trace)
        source = File.read(trace)
        begin
          program = Compiler::Parser.new(source).program
          puts program.derivation
          problems = Compiler::Checker.check(program)
          problems.each { |problem| STDERR.puts "#{trace}: #{problem}" }
          return 1 unless problems.empty?
        rescue e : Compiler::Parser::Error
          STDERR.puts e.message
          return 1
        end
        return 0
      end

      if !@robot_to_compile.nil?
        STDERR.puts "Compiling #{@robot_to_compile}"
        source = File.read("#{@robot_to_compile}")
        begin
          parser = Compiler::Parser.new(source)
          costs = @ticks ? Compiler::Interpreter::Costs.crobots : nil
          binfile = Compiler::WASM_Emitter.new(parser.program, costs).to_wasm
        rescue e : Compiler::Parser::Error | Compiler::WASM_Emitter::Unsupported
          STDERR.puts e.message
          return 1
        end
        if @outfile.nil?
          STDOUT.write(binfile)
        else
          File.write("#{@outfile}", binfile)
        end
        return 0
      end

      if @interpreter && (robots = @robots_to_battle)
        status = 0
        robots.each do |file|
          source = File.read(file)
          begin
            program = Compiler::Parser.new(source).program
            problems = Compiler::Checker.check(program)
            unless problems.empty?
              problems.each { |problem| STDERR.puts "#{file}: #{problem}" }
              status = 1
              next
            end
            interpreter = Compiler::Interpreter.new(program, Compiler::NullHost.new, @cycles)
            Compiler::Interpreter.puts_clear
            begin
              interpreter.run
              puts "#{file}: finished after #{interpreter.steps} steps"
            rescue Compiler::Interpreter::StepLimit
              puts "#{file}: stopped at the #{@cycles} step limit"
            end
            captured = Compiler::Interpreter.puts_out
            puts captured unless captured.empty?
          rescue e : Compiler::Parser::Error | Compiler::Interpreter::RuntimeError
            STDERR.puts "#{file}: #{e.message}"
            status = 1
          end
        end
        return status
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

      if Robot.num_robots == 0
        return run_matches(@robots_to_battle.not_nil!)
      end

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

    # Run `@matches` seeded matches on the CROBOTS battlefield and print a
    # summary in the style of `crobots -m`.
    def run_matches(files : Array(String)) : Int32
      entries = [] of {String, String}
      files.each do |file|
        unless File.exists?(file)
          STDERR.puts "#{file}: no such file"
          return 1
        end
        entries << {File.basename(file, ".cr"), File.read(file)}
      end
      if entries.size == 1
        puts "only one robot? cloning a second from #{files[0]}"
        entries << entries[0]
      end
      wins = Array(Int32).new(entries.size, 0)
      ties = Array(Int32).new(entries.size, 0)
      1.upto(@matches) do |m|
        field = Battle::Field.new(entries, seed: @seed + m - 1, limit: @cycles.to_i64)
        field.run
        survivors = field.active
        puts "Match #{m}: seed #{@seed + m - 1}, cycles = #{field.cycles}"
        field.robots.each do |r|
          if (err = r.error)
            puts "  #{r.name}: #{err}"
          end
        end
        if survivors.empty?
          puts "  mutual destruction"
        else
          survivors.each { |r| puts "  survivor #{r.name}: damage=#{r.damage}%" }
        end
        field.robots.each_with_index do |r, i|
          next unless r.active
          survivors.size == 1 ? (wins[i] += 1) : (ties[i] += 1)
        end
      end
      puts "Cumulative score:"
      entries.each_with_index { |(name, _), i| puts "  #{name}: wins=#{wins[i]} ties=#{ties[i]}" }
      0
    end

    def customize_parser(parser)
      parser.banner = "Welcome to Crystal Robots!\nUsage: crystal-robots [options] robot-source-file-1 [..2 [..3 [robot-source-file-4]]] [>file]"
      parser.on "-v", "--version", "Show version and check-in" do
        puts CrystalRobots.version_line
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
      parser.on "-t ROBOT", "--trace=ROBOT", "Print the parser derivation of ROBOT, one line per pass" do |robot|
        @robot_to_trace = robot
      end
      parser.on "-c ROBOT", "--compile=ROBOT", "Compile robot source only and output WebAssembly (WASM); see -o" do |robot|
        @robot_to_compile = robot
      end
      parser.on "--ticks", "With -c: import env.tick and charge CROBOTS cycles, so a host can count or schedule" do
        @ticks = true
      end
      parser.on "-o OUTFILE", "--output=OUTFILE", "Write compiled robot to OUTFILE" do |outfile|
        @outfile = outfile
      end
      parser.on "-m MATCHES", "--matches=MATCHES", "Run MATCHES matches" do |matches|
        @matches = matches.to_i32
      end
      parser.on "-l CYCLES", "--limit=CYCLES", "Set virtual machine cycle limit to CYCLES. Default is 500,000." do |cycles|
        @cycles = cycles.to_i32
      end
      parser.on "--seed=SEED", "Random seed for the first match (default 1); later matches add 1" do |seed|
        @seed = seed.to_u64
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

    # The CLI runs from an at_exit handler so that robots compiled natively
    # with the prelude get a chance to register first. A non-zero status
    # from `run` becomes the process exit code.
    def run_at_exit
      at_exit do
        status = run
        exit(status) if status.is_a?(Int32) && status != 0
      end
    end
  end
end
