require "./crystal-robots"

at_exit do
  CrystalRobots::CLI.new
end
