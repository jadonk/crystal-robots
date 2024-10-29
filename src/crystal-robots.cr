require "option_parser"
require "crystal_robots"

# TODO: http://tpoindex.github.io/crobots/docs/crobots_manual.html#4
OptionParser.parse do |parser|
  parser.banner = "Welcome to Crystal Robots!"

  parser.on "-v", "--version", "Show version" do
    puts CrystalRobots::VERSION
    exit
  end
  parser.on "-h", "--help", "Show help" do
    puts parser
    exit
  end
end
