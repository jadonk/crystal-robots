require "option_parser"
require "crystal_robots"

matches = 1
cycles = 500_000
robot = nil
robots = nil

# TODO: http://tpoindex.github.io/crobots/docs/crobots_manual.html#4
parser = OptionParser.new do |parser|
  parser.banner = "Welcome to Crystal Robots!\nUsage: crystal-robots [options] robot-source-file-1 [robot-source-file-n] [>file]"
  parser.on "-v", "--version", "Show version" do
    puts CrystalRobots::VERSION
    exit
  end
  parser.on "-h", "--help", "Show help" do
    puts parser
    exit
  end
  parser.on "-c ROBOT", "--compile=ROBOT", "Compile robot source only and output WebAssembly (WASM)" do |robot|
    # TODO: call the compiler and output .WASM with symbol tables
    STDERR.puts "Compiling #{robot}"
    exit
  end
  parser.on "-m MATCHES", "--matches=MATCHES", "Run MATCHES matches" do |matches|
    # TODO: run the battlefield simulator repeatedly
    puts "Running #{matches} matches"
  end
  parser.on "-l CYCLES", "--limit=CYCLES", "Set virtual machine cycle limit to CYCLES. Default is 500,000." do |cycles|
    # TODO: count cycles and enable setting the limit
    puts "Limiting virtual machine cycles to #{cycles}"
  end
  parser.unknown_args do |args, _|
    if args.size > 0
      robots = args
      puts "Running with robots: #{robots}"
    end
  end
end

parser.parse

if robots.nil?
  puts parser
  exit 1
end
