require "./crystal-robots"
require "./web/cgi"

# Under Fossil's /ext extension mechanism the same binary is the web app.
if ENV["GATEWAY_INTERFACE"]?
  CrystalRobots::Web::CGI.new.serve
  exit 0
end

c = CrystalRobots::CLI.new
c.run_at_exit
