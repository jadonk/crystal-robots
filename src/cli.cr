require "./version"

if ARGV.includes?("--version") || ARGV.includes?("-v")
  puts "crystal-robots #{CrystalRobots::VERSION}"
else
  puts "crystal-robots #{CrystalRobots::VERSION}: nothing to do yet"
end
