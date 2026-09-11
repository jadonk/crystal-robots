require "./crystal-robots"
require "./web/cgi"

# Under Fossil's /ext extension mechanism the same binary is the web app.
if ENV["GATEWAY_INTERFACE"]?
  CrystalRobots::Web::CGI.new.serve
  exit 0
end

# `bin/crystal-robots build-docs`: generate the API docs into docs-api/ so
# the next `shards build` embeds them (see src/web/docs.cr).
if ARGV[0]? == "build-docs"
  ok = CrystalRobots::Web::Docs.build("#{CrystalRobots::VERSION} #{CrystalRobots.checkin_short}")
  puts(ok ? "docs written to #{CrystalRobots::Web::Docs::DIR}; run `shards build` to embed them" : "crystal docs failed")
  exit(ok ? 0 : 1)
end

c = CrystalRobots::CLI.new
c.run_at_exit
