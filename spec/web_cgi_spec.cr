require "./spec_helper"
require "../src/web/cgi"
require "uri"

private def run_cgi(caps : String, path : String, method = "GET", query = "", body = "", script = "/ext/robots", user = "jkridner") : String
  env = {
    "GATEWAY_INTERFACE"   => "CGI/1.1",
    "REQUEST_METHOD"      => method,
    "PATH_INFO"           => path,
    "QUERY_STRING"        => query,
    "SCRIPT_NAME"         => script,
    "FOSSIL_CAPABILITIES" => caps,
    "FOSSIL_USER"         => user,
    "CONTENT_LENGTH"      => body.bytesize.to_s,
  }
  reply = IO::Memory.new
  CrystalRobots::Web::CGI.new(env, reply, IO::Memory.new(body)).serve
  reply.to_s
end

private def run_tournament(caps : String, query : String, wiki : CrystalRobots::Web::WikiRobots? = nil, user = "jkridner", script = "/ext/robots") : String
  env = {
    "GATEWAY_INTERFACE" => "CGI/1.1", "REQUEST_METHOD" => "GET", "PATH_INFO" => "/tournament",
    "QUERY_STRING" => query, "SCRIPT_NAME" => script, "FOSSIL_CAPABILITIES" => caps, "FOSSIL_USER" => user,
  }
  reply = IO::Memory.new
  cgi = CrystalRobots::Web::CGI.new(env, reply)
  cgi.wiki = wiki if wiki
  cgi.serve
  reply.to_s
end

private def run_next_round(reply : String, caps : String, wiki : CrystalRobots::Web::WikiRobots?, script = "/ext/robots") : String
  link = reply.lines.find { |l| l.includes?("Run next round") }.not_nil!
  url = link.match(/\]\((.*?)\)/).not_nil![1]
  query = url.split("?", 2)[1]
  run_tournament(caps, query, wiki, script: script)
end

private def run_start_round1(reply : String, caps : String, wiki : CrystalRobots::Web::WikiRobots?, script = "/ext/robots") : String
  url = reply.match(/<a href="(.*?)"><button/).not_nil![1]
  query = url.split("?", 2)[1]
  run_tournament(caps, query, wiki, script: script)
end

SAVED_ROBOTS = {
  "robot/spinner" => "```crystal\nmain(\"Spinner\") do\n  while true\n    drive(90, 30)\n  end\nend\n```\n",
  "robot/zigzag"  => "```crystal\nmain(\"Zigzag\") do\n  while true\n    drive(45, 40)\n    sleep\n    drive(135, 40)\n    sleep\n  end\nend\n```\n",
}

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
    reply.should contain "# counter\n"
    reply.should contain "main(\"Counter\") do"
    reply.should contain "## Derivation"
    reply.should contain "  0 lex "
    reply.should contain "Checks passed"
  end

  it "returns 404 for an unknown example" do
    run_cgi("o", "/examples/nope").should start_with "Status: 404"
  end

  it "parses posted source and shows errors with a location" do
    ok = run_cgi("oi", "/parse", "POST", "", "source=puts+1%2B2")
    ok.should contain "  1 add "
    bad = run_cgi("oi", "/parse", "POST", "", "source=if+x%0Aputs+1")
    bad.should contain "**Parse error:** Cannot reduce"
    bad.should contain "at 1:1"
  end

  it "shows the battle form and runs a seeded match with a Pikchr frame" do
    form = run_cgi("oi", "/battle")
    form.should contain "name=\"r\" value=\"counter\""
    form.should contain "action=\"/ext/robots/battle\""
    page = run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000")
    page.should contain "# Battle: counter vs target"
    page.should contain "```pikchr"
    page.should contain "R1: circle"
    page.should contain "| counter |"
    page.should contain "[Pick again](/ext/robots/battle)"
    again = run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000")
    again.should eq page
    first = run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000&frame=0")
    first.should contain "## Frame 1 of"
    moved = run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=40000")
    moved.should contain "line thin color" # trails, once a robot has moved
    # animation first, static frame second, result last
    page.index("<svg ").not_nil!.should be < page.index("```pikchr").not_nil!
    page.index("```pikchr").not_nil!.should be < page.index("## Result").not_nil!
    page.should contain "<animateTransform attributeName=\"transform\" type=\"translate\""
    page.should contain "type=\"rotate\""
    page.should contain "repeatCount=\"indefinite\""
    page.should contain "| cannon |"
  end

  it "lets a pasted robot fight and reports its problems" do
    src = URI.encode_www_form("main(\"Me\") do\n  while true\n    drive(90, 50)\n  end\nend\n")
    page = run_cgi("oi", "/battle", "GET", "r=target&src=#{src}&seed=1&limit=1500")
    page.should contain "# Battle: yours vs target"
    page.should contain "src=main"
    broken = run_cgi("oi", "/battle", "GET", "src=#{URI.encode_www_form("puts nope\n")}&limit=300")
    broken.should contain "| yours | failed |"
    broken.should contain "undefined variable or function nope at 1:6"
    checked = run_cgi("oi", "/parse", "POST", "", "source=puts+nope")
    checked.should contain "**Problems:**"
  end

  it "cannot be broken out of a code fence or a table by user text" do
    evil = URI.encode_www_form("puts 1\n```\n# injected heading\n<script>x</script>\n")
    page = run_cgi("oi", "/parse", "POST", "", "source=#{evil}")
    # the whole user text sits inside a fence one backtick longer than its own
    page.should contain "````crystal\nputs 1\n```\n# injected heading\n<script>x</script>\n````\n"
    outside = page.split("````").each_slice(2).map(&.first).join
    outside.should_not contain "injected"
    outside.should_not contain "<script>"
    fight = run_cgi("oi", "/battle", "GET", "src=#{URI.encode_www_form("main(\"M\") do\n  puts \"a | b <b>c</b> `d`\"\n  while true\n    sleep\n  end\nend\n")}&limit=300")
    fight.should contain "puts a &#124; b &lt;b&gt;c&lt;/b&gt; &#96;d&#96;"
  end

  it "bounds the request body and the source size" do
    big = "x" * 70_000
    run_cgi("oi", "/parse", "POST", "", "source=#{big}").should start_with "Status: 400 Bad Request"
    huge = "source=" + URI.encode_www_form("puts 1\n" * 4_000)
    run_cgi("oi", "/parse", "POST", "", huge).should contain "the limit is 20000"
    run_cgi("oi", "/parse", "GET", "source=puts+1").should contain "Nothing to parse"
  end

  it "answers 400 to invalid UTF-8 instead of crashing" do
    run_cgi("oi", "/parse", "POST", "", "source=\xff\xfe").should start_with "Status: 400 Bad Request"
    run_cgi("oi", "/battle", "GET", "r=\xff").should start_with "Status: 400 Bad Request"
    run_cgi("o", "/examples/\xff").should start_with "Status: 400 Bad Request"
  end

  it "keeps parse and battle for logged-in users, and says so up front" do
    # anonymous, nobody and the not-logged-in visitor hold read letters only
    ["anonymous", "nobody", ""].each do |who|
      run_cgi("oh", "/parse", "POST", "", "source=puts+1", user: who).should start_with "Status: 403 Forbidden\r\nContent-Type: text/x-markdown"
      run_cgi("oh", "/battle", "GET", "r=counter&r=target", user: who).should contain "[Log in](/login?g=%2Fext%2Frobots%2Fbattle)"
      run_cgi("oh", "/examples/target", user: who).should contain "# target\n"
      front = run_cgi("oh", "/", user: who)
      front.should_not contain "<form"
      front.should contain "[log in](/login?g=%2Fext%2Frobots)"
    end
    run_cgi("ohi", "/").should contain "<form"
    # a named user without check-in sees why, not a login link
    without = run_cgi("oh", "/battle", "GET", "r=counter&r=target")
    without.should start_with "Status: 403"
    without.should contain "check-in permission (`i`)"
    without.should_not contain "[Log in]"
    run_cgi("oh", "/").should contain "ask the maintainer"
    run_cgi("oh", "/").should_not contain "<form"
    # developer and admin expansions carry i
    run_cgi("v", "/battle", "GET", "r=counter&r=target&limit=300").should contain "# Battle"
    run_cgi("a", "/battle", "GET", "r=counter&r=target&limit=300").should contain "# Battle"
  end

  it "shows a bounded derivation from the one parse, even on a budget error" do
    C::Parser.max_glyphs = 80_000
    begin
      page = run_cgi("oi", "/parse", "POST", "", "source=" + URI.encode_www_form("puts " + "1+" * 400 + "1"))
      page.should contain "**Parse error:** Program is too large to parse"
      page.should contain "passes elided"
      page.should contain "more)" # long lines cut
      page.lines.count { |l| l =~ /^\s+\d+ / }.should be <= 60
      page.size.should be < 60_000
    ensure
      C::Parser.max_glyphs = 2_000_000
    end
  end

  it "plays the replay at a chosen pace in cycles per second with growing trails" do
    page = run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000&cps=100")
    page.should contain "replay at 100 cycles per second (30.0 s)"
    page.should contain "dur=\"30.0s\""
    page.should contain "stroke-dashoffset"
    page.should contain "&cps=100&frame="
    run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000&cps=99999").should contain "replay at 20000 cycles per second"
    run_cgi("oi", "/battle", "GET", "r=counter&r=target&seed=3&limit=3000").should contain "replay at 300 cycles per second (10.0 s)"
  end

  it "runs a series of matches with a score table like crobots -m" do
    page = run_cgi("oi", "/battle", "GET", "r=counter&r=rabbit&seed=4&limit=3000&matches=3")
    page.should contain "# Series: counter vs rabbit"
    page.should contain "seeds 4 to 6"
    page.should contain "| counter |"
    page.lines.count { |l| l.starts_with?("| 1 |") || l.starts_with?("| 2 |") || l.starts_with?("| 3 |") }.should eq 3
    page.should contain "[replay](/ext/robots/battle?r=counter&r=rabbit&seed=5&limit=3000&cps=300&frame=0)"
    # the series work cap trims the number of matches
    capped = run_cgi("oi", "/battle", "GET", "r=counter&r=rabbit&seed=4&limit=500000&matches=10")
    capped.should contain "1 matches"
    capped.should contain "9 more dropped"
  end

  it "offers robots saved as wiki pages and battles them" do
    pages = {
      "robot/spinner" => "# Spinner\n\nTurns forever.\n\n```crystal\nmain(\"Spinner\") do\n  while true\n    drive(90, 30)\n  end\nend\n```\n",
      "robot/broken"  => "two blocks\n\n```\nputs 1\n```\n\n```\nputs 2\n```\n",
      "Home"          => "not a robot",
    }
    pages["robot/bad \"name\""] = "```\nputs 1\n```\n"
    pages["robot/huge"] = "```\n" + "puts 1\n" * 4_000 + "```\n"
    wiki = CrystalRobots::Web::WikiRobots.from_pages(pages)
    wiki.names.should eq ["broken", "huge", "spinner"] # the quoted name is not a robot name
    wiki.source("huge").should be_nil                  # over the source size cap
    wiki.source("spinner").not_nil!.should start_with "main(\"Spinner\")"
    wiki.source("broken").should be_nil
    wiki.source("Home").should be_nil
    env = {"PATH_INFO" => "/", "SCRIPT_NAME" => "/ext/robots", "FOSSIL_CAPABILITIES" => "ohij", "FOSSIL_USER" => "jkridner"}
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env, reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should contain "[spinner](/ext/robots/wiki/spinner)"
    reply.to_s.should contain "| Turns forever. |"
    reply.to_s.should contain "[fight](/ext/robots/battle?pick=spinner)"
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => "/battle", "QUERY_STRING" => "pick=spinner"}), reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should contain "value=\"spinner\" checked"
    reply.to_s.should_not contain "value=\"counter\" checked"
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => "/battle", "QUERY_STRING" => "w=spinner&r=target&limit=1500"}), reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should contain "# Battle: target vs spinner"
    reply.to_s.should contain "w=spinner"
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => "/wiki/spinner"}), reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should contain "# spinner"
    reply.to_s.should contain "Checks passed"
    reply.to_s.should contain "[Fight it against counter and rabbit](/ext/robots/battle?w=spinner&r=counter&r=rabbit)"
    reply.to_s.should contain "(/wikiedit?name=robot%2Fspinner)"
    # wiki reads need a login and the wiki-read capability
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => "/wiki/spinner", "FOSSIL_USER" => "anonymous", "FOSSIL_CAPABILITIES" => "ohj"}), reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should start_with "Status: 403"
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => "/", "FOSSIL_CAPABILITIES" => "oi"}), reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should_not contain "Saved robots"
    reply = IO::Memory.new
    cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => "/battle", "QUERY_STRING" => "w=spinner&r=target&limit=300", "FOSSIL_CAPABILITIES" => "oi"}), reply)
    cgi.wiki = wiki
    cgi.serve
    reply.to_s.should contain "# Battle: target vs target" # w= ignored without wiki-read
  end

  it "escapes names in Pikchr labels" do
    cgi = CrystalRobots::Web::CGI.new({} of String => String, IO::Memory.new)
    cgi.pikchr_text(%q(a "quoted" \ name)).should eq %q(a \"quoted\" \\ name)
    cgi.pikchr_text("x" * 100).size.should eq 40
  end

  it "unwraps headings so rotations take the short way round" do
    cgi = CrystalRobots::Web::CGI.new({} of String => String, IO::Memory.new)
    cgi.unwrap([350, 10, 20, 200, 190]).should eq [350, 370, 380, 560, 550]
    cgi.unwrap([-10, -350]).should eq [-10, 10]
  end

  it "serves the embedded API docs inside the Fossil chrome, or says they were not built" do
    if CrystalRobots::Web::Docs.built?
      run_cgi("oh", "/docs").should start_with "Status: 302 Found\r\nLocation: /ext/robots/docs/index.html"
      index = run_cgi("oh", "/docs/index.html")
      index.should start_with "Status: 200 OK\r\nContent-Type: text/html"
      index.should contain "<div class='fossil-doc' data-title='crystal-robots"
      index.should_not contain "<script"
      index.should_not contain "<input"
      index.should contain "types-list"
      page = run_cgi("oh", "/docs/CrystalRobots/Compiler/Parser.html")
      page.should contain "data-title='CrystalRobots::Compiler::Parser'"
      page.should contain "One reduction pass"                             # the doc comment survives
      run_cgi("oh", "/docs/css/style.css").should start_with "Status: 404" # replaced by inline styles
      run_cgi("oh", "/docs/js/doc.js").should start_with "Status: 404"
      run_cgi("oh", "/docs/../secret").should start_with "Status: 404"
      run_cgi("oh", "/").should contain "[API reference](/ext/robots/docs/index.html)"
    else
      run_cgi("oh", "/docs").should start_with "Status: 404"
      run_cgi("oh", "/docs").should contain "build-docs"
    end
    run_cgi("oh", "/docs/nope.html").should start_with "Status: 404"
  end

  it "reports version and check-in" do
    v = run_cgi("oh", "/version")
    v.should contain "crystal-robots #{CrystalRobots::VERSION} (check-in "
    CrystalRobots.checkin_short.size.should be <= 10
    run_cgi("oh", "/").should contain "check-in `#{CrystalRobots.checkin_short}`"
  end

  it "parses wiki artifacts from the single SQL read" do
    artifact = "D 2026-09-10T23:46:09.118\nL robot/turret\nN text/x-markdown\nU agent-claude\nW 12\n# Turret\n\nhi\nZ abc\n"
    CrystalRobots::Web::WikiRobots.wiki_text(artifact).should eq "# Turret\n\nhi"
    CrystalRobots::Web::WikiRobots.wiki_text("D 1\nL robot/x\nW 0\n\nZ a\n").should be_nil
  end

  it "splits SQL rows at the LAST space, so a robot name with a space in it does not break the listing" do
    text = "```\nmain(\"Wall Hugger\") do\n  drive(0, 30)\nend\n```\n"
    artifact = "D 2026-09-11T00:00:00.000\nL robot/wall hugger\nN text/x-markdown\nU agent-claude\nW #{text.bytesize}\n#{text}Z deadbeef\n"
    live_row = "robot/wall hugger #{artifact.to_slice.hexstring}"
    # a deleted page keeps its tag but its latest artifact has an empty W
    # payload; it must not appear as a robot, and it must not break the row
    # before or after it either.
    deleted = "D 2026-09-11T00:01:00.000\nL robot/old design\nW 0\n\nZ cafebabe\n"
    deleted_row = "robot/old design #{deleted.to_slice.hexstring}"
    pages = CrystalRobots::Web::WikiRobots.parse_rows("#{live_row}\n#{deleted_row}\n")
    pages.keys.should eq ["wall hugger"]
    pages["wall hugger"].should eq text
    wiki = CrystalRobots::Web::WikiRobots.new(pages)
    wiki.names.should eq ["wall hugger"]
    wiki.source("wall hugger").not_nil!.should contain "Wall Hugger"
    env = {"PATH_INFO" => "/", "SCRIPT_NAME" => "/ext/robots", "FOSSIL_CAPABILITIES" => "ohij", "FOSSIL_USER" => "jkridner"}
    [
      {"/", ""},
      {"/battle", "w=wall+hugger&r=target&limit=300"},
      {"/wiki/wall%20hugger", ""},
    ].each do |(p, qs)|
      reply = IO::Memory.new
      cgi = CrystalRobots::Web::CGI.new(env.merge({"PATH_INFO" => p, "QUERY_STRING" => qs}), reply)
      cgi.wiki = wiki
      cgi.serve
      reply.to_s.should start_with "Status: 200"
    end
  end

  it "re-roots links under a session preview path" do
    reply = run_cgi("oi", "/", "GET", "", "", "/crystal-robots/ext/preview/session-abc")
    reply.should contain "[counter.cr](/ext/preview/session-abc/examples/counter)"
    # raw HTML is not rewritten by Fossil, so the form needs the full path
    reply.should contain "action=\"/crystal-robots/ext/preview/session-abc/parse\""
  end

  describe "/tournament" do
    it "shows big checkboxes for examples and saved robots, with an everyone link and a Start button" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      form = run_tournament("oij", "", wiki)
      form.should start_with "Status: 200 OK\r\nContent-Type: text/x-markdown\r\n\r\n# Tournament"
      form.should contain "name=\"r\" value=\"counter\""
      form.should contain "name=\"w\" value=\"spinner\""
      form.should contain "Check everyone"
      form.should contain "<button type=\"submit\""
      form.should_not contain "disabled"
      form.should contain "<details><summary>More choices</summary>"
      form.should_not contain "<script"
    end

    it "gives read-only users the picker with Start disabled and a plain-word note, and refuses an actual run" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      form = run_tournament("oh", "", wiki)
      form.should contain "name=\"r\" value=\"counter\""
      form.should contain "<button type=\"submit\" disabled"
      form.should contain "Running a tournament needs check-in permission (`i`)"
      run = run_tournament("oh", "r=counter&r=rabbit&r=rook&seed=1", wiki)
      run.should start_with "Status: 403"
      # an anonymous/not-logged-in visitor sees a log-in note instead
      anon = run_tournament("oh", "", wiki, user: "anonymous")
      anon.should contain "[log in]"
    end

    it "rejects fewer than 3 robots and a saved robot with no code block, in plain words" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS.merge({"robot/broken" => "two blocks\n\n```\nputs 1\n```\n\n```\nputs 2\n```\n"}))
      few = run_tournament("oij", "r=counter&r=rabbit&seed=1", wiki)
      few.should contain "Pick at least 3 robots to start a tournament."
      broken = run_tournament("oij", "r=counter&r=rabbit&w=broken&seed=1", wiki)
      broken.should contain "broken has no code block yet."
    end

    it "shows the tournament's shareable link and a Start round 1 button before any fight runs" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      query = "r=counter&r=rabbit&r=rook&r=sniper&seed=1&limit=30000"
      link_page = run_tournament("oij", query, wiki)
      link_page.should start_with "Status: 200 OK\r\nContent-Type: text/x-markdown\r\n\r\n# Tournament"
      link_page.should contain "/ext/robots/tournament?r=counter&r=rabbit&r=rook&r=sniper&seed=1&limit=30000"
      link_page.should contain "Start round 1"
      link_page.should_not contain "### Pool"
      link_page.should_not contain "pikchr"
      link_page.should_not contain "```"
    end

    it "re-roots every link correctly under a preview path: Markdown links stay under /ext/ (Fossil prefixes them with the repo root), raw href/action attributes carry the full script path (Fossil leaves raw HTML untouched)" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      script = "/crystal-robots/ext/preview/task-9"

      designer = run_tournament("oij", "", wiki, script: script)
      designer.scan(/\]\(([^)]+)\)/).each { |m| m[1].should start_with "/ext/" }
      designer.scan(/(?:href|action)="([^"]+)"/).each { |m| m[1].should start_with "/crystal-robots/ext/" }

      query = "r=counter&r=rabbit&r=rook&r=sniper&seed=1&limit=30000"
      link_page = run_tournament("oij", query, wiki, script: script)
      link_page.scan(/\]\(([^)]+)\)/).each { |m| m[1].should start_with "/ext/" }
      link_page.scan(/(?:href|action)="([^"]+)"/).each { |m| m[1].should start_with "/crystal-robots/ext/" }
      # the shareable link shown as plain text is a full absolute URL, so it can be copied and pasted anywhere
      link_page.should contain "http://localhost/crystal-robots/ext/preview/task-9/tournament?#{query}"

      pools = run_start_round1(link_page, "oij", wiki, script: script)
      pools.scan(/\]\(([^)]+)\)/).each { |m| m[1].should start_with "/ext/" }
      pools.scan(/(?:href|action)="([^"]+)"/).each { |m| m[1].should start_with "/crystal-robots/ext/" }
    end

    it "round-trips the URL: the same query always replays the same stage, and the run-next-round link carries the advancing state forward" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      query = "r=counter&r=rabbit&r=rook&r=sniper&seed=1&limit=30000"
      link_page = run_tournament("oij", query, wiki)
      pools = run_start_round1(link_page, "oij", wiki)
      pools.should contain "The pools are done."
      again = run_start_round1(link_page, "oij", wiki)
      again.should eq pools      # same URL, same result: no hidden state
      pools.should contain "mv=" # the run-next-round link carries the decided outcomes forward
      pools.should_not contain "pool="
      pools.should_not contain "rnd="

      round1 = run_next_round(pools, "oij", wiki)
      round1.should contain "mv=" # carried through (replayed for free), not recomputed with new fights
      round1.should_not contain "The pools are done."

      # the link that plays this round again (same slots, same resume seed) reproduces it exactly
      link = pools.lines.find { |l| l.includes?("Run next round") }.not_nil!
      url = link.match(/\]\((.*?)\)/).not_nil![1]
      replay_query = url.split("?", 2)[1]
      round1_again = run_tournament("oij", replay_query, wiki)
      round1_again.should eq round1
    end

    it "plays a full 8-robot tournament to a champion across one-round-per-request pages, with no JS tag anywhere" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      query = "r=counter&r=rabbit&r=rook&r=sniper&r=target&r=test&w=spinner&w=zigzag&seed=1&limit=30000"
      link_page = run_tournament("oij", query, wiki)
      page = run_start_round1(link_page, "oij", wiki)
      pages = [page]

      stages = 0
      until page.includes?("wins the Tournament")
        stages += 1
        stages.should be <= 6 # 2 pools -> semifinal -> final is 3 stages; this is a generous ceiling
        page = run_next_round(page, "oij", wiki)
        pages << page
      end

      pages.each do |p|
        p.should start_with "Status: 200 OK\r\nContent-Type: text/x-markdown\r\n\r\n"
        p.should contain "[Back](/ext/robots)"
        p.should_not contain "<script"
      end
      pages.first.should contain "### Pool A:"
      pages.first.should contain "### Pool B:"

      final = pages.last
      final.should contain "wins the Tournament"
      final.should contain "```pikchr\nCUP:"   # the trophy picture
      final.should contain "```pikchr\nboxwid" # the ladder picture
      final.should contain "### Final"
      final.should contain "[replay](/ext/robots/battle?" # every fight links to its replay
      final.should_not contain "Run next round"           # nothing left to do
      final.should contain "arrow from RD"                # bracket arrows connect each round to the next
      final.should contain ".s to CH.n"                   # ...and the final round to the champion
    end

    it "round-trips through the outcome string: the same link replays with no new fights and reproduces the exact same page" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS)
      query = "r=counter&r=rabbit&r=rook&r=sniper&seed=1&limit=30000"
      link_page = run_tournament("oij", query, wiki)
      pools = run_start_round1(link_page, "oij", wiki)

      link = pools.lines.find { |l| l.includes?("Run next round") }.not_nil!
      mv_query = link.match(/\]\((.*?)\)/).not_nil![1].split("?", 2)[1]
      mv_query.should match(/(^|&)mv=[abt]+(&|$)/) # a compact letters-only outcome string, not a serialized blob

      first = run_tournament("oij", mv_query, wiki)
      second = run_tournament("oij", mv_query, wiki)
      first.should eq second # a pure function of entrants + seed + limit + outcomes: no hidden state
    end

    it "keeps every link comfortably under Fossil's request-line limit for an 11-robot tournament" do
      wiki = CrystalRobots::Web::WikiRobots.from_pages(SAVED_ROBOTS.merge({
        "robot/orbiter" => "```crystal\nmain(\"Orbiter\") do\n  while true\n    drive(0, 20)\n  end\nend\n```\n",
        "robot/dodger"  => "```crystal\nmain(\"Dodger\") do\n  while true\n    drive(180, 25)\n  end\nend\n```\n",
        "robot/charger" => "```crystal\nmain(\"Charger\") do\n  while true\n    drive(270, 35)\n  end\nend\n```\n",
      }))
      query = "r=counter&r=rabbit&r=rook&r=sniper&r=target&r=test&w=spinner&w=zigzag&w=orbiter&w=dodger&w=charger&seed=1&limit=30000"
      link_page = run_tournament("oij", query, wiki)
      page = run_start_round1(link_page, "oij", wiki)
      pages = [link_page, page]

      stages = 0
      until page.includes?("wins the Tournament")
        stages += 1
        stages.should be <= 5 # 1 pool stage + up to 3 bracket rounds; a generous ceiling
        page = run_next_round(page, "oij", wiki)
        pages << page
      end

      links = pages.flat_map { |p| p.scan(/\]\(([^)]+)\)/).map { |m| m[1] } + p.scan(/href="([^"]+)"/).map { |m| m[1] } }
      tournament_links = links.select { |l| l.includes?("/tournament") }
      tournament_links.should_not be_empty
      tournament_links.each { |l| l.bytesize.should be < 1500 }
    end
  end
end
