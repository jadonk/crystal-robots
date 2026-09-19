require "option_parser"
require "./version"
require "./compiler/program"
require "./compiler/parser"
require "./compiler/checker"
require "./compiler/interpreter"
require "./compiler/wasm_emitter"
require "./compiler/disassembler"
require "./battle/field"
require "./battle/match"
require "./web/cgi"
require "./web/docs"

module CrystalRobots::CLI
  private def self.parsed_program(file : String) : Compiler::Program
    Compiler::Parser.new(File.read(file)).program
  rescue e : Compiler::Parser::Error
    abort e.message
  end

  # Parses and checks `file`, printing every issue and exiting nonzero if
  # the checker finds any -- the gate `-c` and `-i` both run through
  # before compiling or interpreting a program that does not mean
  # anything.
  private def self.checked_program(file : String) : Compiler::Program
    program = parsed_program(file)
    issues = Compiler::Checker.check(program)
    unless issues.empty?
      issues.each { |issue| STDERR.puts issue.to_s }
      exit 1
    end
    program
  end

  def self.run(argv : Array(String)) : Nil
    mode = :help
    output = nil
    matches = 1
    cycle_limit = 500_000
    seed = nil
    parser = OptionParser.new do |p|
      p.banner = "Usage: crystal-robots [options] FILE..."
      p.on("-v", "--version", "Print the version and check-in") { puts CrystalRobots.version_line; exit }
      p.on("-t", "--trace", "Print the parser's derivation, one line per pass") { mode = :trace }
      p.on("-k", "--check", "Run the checker and print any issues found") { mode = :check }
      p.on("-c", "--compile", "Compile to a WebAssembly module (needs -o)") { mode = :compile }
      p.on("-d", "--disassemble", "Compile and print a readable instruction dump") { mode = :disassemble }
      p.on("-i", "--interpret", "Run in the reference interpreter") { mode = :interpret }
      p.on("-o FILE", "--output=FILE", "Where -c writes the WebAssembly module") { |f| output = f }
      p.on("-m NUM", "--matches=NUM", "Run NUM seeded matches among two or more robots") { |n| matches = n.to_i; mode = :battle }
      p.on("-l NUM", "--limit=NUM", "Cycle limit per match (default 500000)") { |n| cycle_limit = n.to_i }
      p.on("--seed=NUM", "Seed the first match's RNG, for reproducible results") { |n| seed = n.to_i }
      p.on("-h", "--help", "Show this help") { puts p; exit }
    end
    parser.parse(argv)
    file = argv.first?

    case mode
    when :trace
      print parsed_program(file || abort "usage: crystal-robots -t FILE").derivation
    when :check
      issues = Compiler::Checker.check(parsed_program(file || abort "usage: crystal-robots -k FILE"))
      issues.each { |issue| puts issue.to_s }
      puts "no issues found" if issues.empty?
    when :compile
      program = checked_program(file || abort "usage: crystal-robots -c FILE -o OUT")
      out_file = output
      abort("usage: crystal-robots -c FILE -o OUT") unless out_file
      File.write(out_file, Compiler::WASM_Emitter.new(program).to_wasm)
    when :disassemble
      program = checked_program(file || abort "usage: crystal-robots -d FILE")
      print Compiler::Disassembler.disassemble(Compiler::WASM_Emitter.new(program).to_wasm)
    when :interpret
      program = checked_program(file || abort "usage: crystal-robots -i FILE")
      Compiler::Interpreter.execute(program, Compiler::ConsoleHost.new)
    when :battle
      run_matches(argv, matches, cycle_limit, seed)
    else
      puts "#{CrystalRobots.version_line}: nothing to do yet, see --help"
    end
  end

  # Runs `count` seeded matches among the robots in `files` (at least
  # two, each checked first) and prints each match's outcome, then a
  # score table when there is more than one match.
  private def self.run_matches(files : Array(String), count : Int32, cycle_limit : Int32, seed : Int32?) : Nil
    abort "usage: crystal-robots -m NUM FILE FILE..." if files.size < 2
    names = files.map { |f| File.basename(f, ".cr") }
    programs = files.map { |f| checked_program(f) }
    wins = Hash(String, Int32).new(0)

    count.times do |i|
      match_seed = seed ? seed + i : nil
      field = Battle::Field.new(names, match_seed)
      match = Battle::Match.new(field, programs, cycle_limit: cycle_limit)
      match.run
      survivors = field.robots.select(&.alive?)
      report = "match #{i + 1}: #{match.rounds} rounds, " + field.robots.map { |r| "#{r.name} #{r.damage}%#{" (dead)" unless r.alive?}" }.join(", ")
      if survivors.size == 1
        wins[survivors[0].name] += 1
        puts "#{report} -- #{survivors[0].name} wins"
      else
        puts "#{report} -- no winner"
      end
    end

    if count > 1
      puts "\nscore:"
      names.each { |n| puts "  #{n}: #{wins[n]}" }
    end
  end
end

# One binary: Fossil sets GATEWAY_INTERFACE for a CGI request; anything
# else is the command-line tool.
if ENV["GATEWAY_INTERFACE"]?
  CrystalRobots::Web::CGI.run
elsif ARGV[0]? == "build-docs"
  # Generates the API docs into docs-api/ so the *next* `shards build`
  # embeds them (see src/web/docs.cr) -- this run cannot embed its own
  # output, since CrystalRobots::Web::Docs::FILES is read once, at the
  # compile time of the binary already running.
  ok = CrystalRobots::Web::Docs.build("#{CrystalRobots::VERSION} #{CrystalRobots.checkin_short}")
  puts(ok ? "docs written to #{CrystalRobots::Web::Docs::DIR}; run `shards build` to embed them" : "crystal docs failed")
  exit(ok ? 0 : 1)
else
  CrystalRobots::CLI.run(ARGV)
end
