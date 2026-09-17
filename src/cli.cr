require "./version"
require "./compiler/program"
require "./compiler/parser"

if ARGV.includes?("--version") || ARGV.includes?("-v")
  puts "crystal-robots #{CrystalRobots::VERSION}"
elsif ARGV.includes?("-t")
  file = ARGV.reject(&.starts_with?("-")).first? || abort "usage: crystal-robots -t FILE"
  program = CrystalRobots::Compiler::Parser.new(File.read(file)).program
  print program.derivation
else
  puts "crystal-robots #{CrystalRobots::VERSION}: nothing to do yet"
end
