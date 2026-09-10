require "./spec_helper"
require "../src/web/cgi"

private def run_cgi(caps : String, path : String, method = "GET", query = "", body = "", script = "/ext/robots") : String
  env = {
    "GATEWAY_INTERFACE"   => "CGI/1.1",
    "REQUEST_METHOD"      => method,
    "PATH_INFO"           => path,
    "QUERY_STRING"        => query,
    "SCRIPT_NAME"         => script,
    "FOSSIL_CAPABILITIES" => caps,
    "FOSSIL_USER"         => "jkridner",
    "CONTENT_LENGTH"      => body.bytesize.to_s,
  }
  reply = IO::Memory.new
  CrystalRobots::Web::CGI.new(env, reply, IO::Memory.new(body)).serve
  reply.to_s
end

describe CrystalRobots::Web::CGI do
  it "refuses anonymous users without read capability" do
    reply = run_cgi("", "/")
    reply.should start_with "Status: 403"
    reply.should_not contain "Content-Type: text/x-markdown"
  end

  it "serves the overview as Markdown under the Fossil chrome" do
    reply = run_cgi("oh", "/")
    reply.should start_with "Status: 200 OK\r\nContent-Type: text/x-markdown\r\n\r\n# Crystal Robots"
    reply.should contain "[counter.cr](/ext/robots/examples/counter)"
    reply.should contain "logged in as `jkridner`"
  end

  it "accepts developer, reader, admin and setup capabilities" do
    ["v", "u", "a", "s"].each do |caps|
      run_cgi(caps, "/version").should contain "crystal-robots #{CrystalRobots::VERSION}"
    end
  end

  it "shows an example with its derivation" do
    reply = run_cgi("o", "/examples/counter")
    reply.should contain "# counter.cr"
    reply.should contain "main(\"Counter\") do"
    reply.should contain "## Derivation"
    reply.should contain "  0 lex "
    reply.lines.last.should eq "```"
  end

  it "returns 404 for an unknown example" do
    run_cgi("o", "/examples/nope").should start_with "Status: 404"
  end

  it "parses posted source and shows errors with a location" do
    ok = run_cgi("o", "/parse", "POST", "", "source=puts+1%2B2")
    ok.should contain "  1 add "
    bad = run_cgi("o", "/parse", "POST", "", "source=if+x%0Aputs+1")
    bad.should contain "**Parse error:** Cannot reduce"
    bad.should contain "at 1:1"
  end

  it "re-roots links under a session preview path" do
    reply = run_cgi("o", "/", "GET", "", "", "/crystal-robots/ext/preview/session-abc")
    reply.should contain "[counter.cr](/ext/preview/session-abc/examples/counter)"
  end
end
