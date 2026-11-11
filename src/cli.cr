require "./crystal-robots"
require "./web/cgi"

# Under Fossil's /ext extension mechanism the same binary is the web app.
# OCX's app page (/ext/ocx2-cgi/app/crystal-robots) runs it with only the
# request's fields, with no GATEWAY_INTERFACE, but always with
# FOSSIL_REPOSITORY and REQUEST_METHOD. With an empty environment, as OCX's
# import smokes it, it is the command line, and says `usage: crystal-robots`.
if ENV["GATEWAY_INTERFACE"]? || ENV["FOSSIL_REPOSITORY"]? || ENV["REQUEST_METHOD"]?
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
