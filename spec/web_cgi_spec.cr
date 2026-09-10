require "./spec_helper"
require "../src/web/cgi"
require "uri"

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
    reply.should contain "Checks passed"
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

  it "shows the battle form and runs a seeded match with a Pikchr frame" do
    form = run_cgi("o", "/battle")
    form.should contain "name=\"r\" value=\"counter\""
    form.should contain "action=\"/ext/robots/battle\""
    page = run_cgi("o", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000")
    page.should contain "# Battle: counter vs target"
    page.should contain "```pikchr"
    page.should contain "R1: circle"
    page.should contain "| counter |"
    page.should contain "[Pick again](/ext/robots/battle)"
    again = run_cgi("o", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000")
    again.should eq page
    first = run_cgi("o", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000&frame=0")
    first.should contain "## Frame 1 of"
    page.should contain "line thin color" # trails
  end

  it "lets a pasted robot fight and reports its problems" do
    src = URI.encode_www_form("main(\"Me\") do\n  while true\n    drive(90, 50)\n  end\nend\n")
    page = run_cgi("o", "/battle", "GET", "r=target&src=#{src}&seed=1&limit=1500")
    page.should contain "# Battle: yours vs target"
    page.should contain "src=main"
    broken = run_cgi("o", "/battle", "GET", "src=#{URI.encode_www_form("puts nope\n")}&limit=300")
    broken.should contain "| yours | failed |"
    broken.should contain "undefined variable or function nope at 1:6"
    checked = run_cgi("o", "/parse", "POST", "", "source=puts+nope")
    checked.should contain "**Problems:**"
  end

  it "cannot be broken out of a code fence or a table by user text" do
    evil = URI.encode_www_form("puts 1\n```\n# injected heading\n<script>x</script>\n")
    page = run_cgi("o", "/parse", "POST", "", "source=#{evil}")
    # the whole user text sits inside a fence one backtick longer than its own
    page.should contain "````crystal\nputs 1\n```\n# injected heading\n<script>x</script>\n````\n"
    outside = page.split("````").each_slice(2).map(&.first).join
    outside.should_not contain "injected"
    outside.should_not contain "<script>"
    fight = run_cgi("o", "/battle", "GET", "src=#{URI.encode_www_form("main(\"M\") do\n  puts \"a | b <b>c</b> `d`\"\n  while true\n    sleep\n  end\nend\n")}&limit=300")
    fight.should contain "puts a &#124; b &lt;b&gt;c&lt;/b&gt; &#96;d&#96;"
  end

  it "bounds the request body and the source size" do
    big = "x" * 70_000
    run_cgi("o", "/parse", "POST", "", "source=#{big}").should start_with "Status: 400 Bad Request"
    huge = "source=" + URI.encode_www_form("puts 1\n" * 4_000)
    run_cgi("o", "/parse", "POST", "", huge).should contain "the limit is 20000"
    run_cgi("o", "/parse", "GET", "source=puts+1").should contain "Nothing to parse"
  end

  it "answers 400 to invalid UTF-8 instead of crashing" do
    run_cgi("o", "/parse", "POST", "", "source=\xff\xfe").should start_with "Status: 400 Bad Request"
    run_cgi("o", "/battle", "GET", "r=\xff").should start_with "Status: 400 Bad Request"
    run_cgi("o", "/examples/\xff").should start_with "Status: 400 Bad Request"
  end

  it "re-roots links under a session preview path" do
    reply = run_cgi("o", "/", "GET", "", "", "/crystal-robots/ext/preview/session-abc")
    reply.should contain "[counter.cr](/ext/preview/session-abc/examples/counter)"
    # raw HTML is not rewritten by Fossil, so the form needs the full path
    reply.should contain "action=\"/crystal-robots/ext/preview/session-abc/parse\""
  end
end
