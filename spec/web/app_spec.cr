require "../spec_helper"

alias App = CrystalRobots::Web::App
alias Request = CrystalRobots::Web::Request

private def request(path : String, caps : String = "oi", params = {} of String => String, method = "GET") : Request
  Request.new(method, path, params, "/ext/crystal-robots", "someone", caps)
end

private def post(path : String, params : Hash(String, String), caps : String = "oi") : Request
  request(path, caps: caps, params: params, method: "POST")
end

describe App do
  it "lists every example on the overview, linked under the script name" do
    response = App.handle(request("/"))
    response.status.should eq 200
    response.body.should contain "[hello](/ext/crystal-robots/examples/hello)"
    response.body.should contain "[sniper](/ext/crystal-robots/examples/sniper)"
  end

  it "refuses the overview without read capability" do
    response = App.handle(request("/", caps: ""))
    response.status.should eq 403
  end

  it "404s an unknown path" do
    response = App.handle(request("/nope"))
    response.status.should eq 404
  end

  it "shows an example's source and parse derivation" do
    response = App.handle(request("/examples/hello"))
    response.status.should eq 200
    response.body.should contain "puts 42"
    response.body.should contain "∊№⏎"
    response.body.should contain "⏹"
  end

  it "refuses an example without read capability" do
    App.handle(request("/examples/hello", caps: "")).status.should eq 403
  end

  it "404s an unknown example, and refuses path traversal" do
    App.handle(request("/examples/nope")).status.should eq 404
    App.handle(request("/examples/../cli")).status.should eq 404
  end

  it "shows a parse error instead of crashing on a broken example" do
    response = App.handle(request("/examples/hello"))
    response.status.should eq 200 # sanity: hello.cr itself still parses

    File.write("examples/_spec_broken.cr", ")\n")
    begin
      broken = App.handle(request("/examples/_spec_broken"))
      broken.status.should eq 200
      broken.body.should contain "Could not parse"
    ensure
      File.delete("examples/_spec_broken.cr")
    end
  end

  it "GET /parse shows an empty form" do
    response = App.handle(request("/parse"))
    response.status.should eq 200
    response.body.should contain %(<textarea name="source")
    response.body.should_not contain "Result"
  end

  it "refuses /parse without run capability, even to read" do
    App.handle(request("/parse", caps: "oh")).status.should eq 403
  end

  it "POST /parse shows the derivation and reports no issues for a clean robot" do
    response = App.handle(post("/parse", {"source" => "puts 1 + 2\n"}))
    response.status.should eq 200
    response.body.should contain "∊№⊕№⏎"
    response.body.should contain "No issues found"
  end

  it "POST /parse shows checker issues for a robot that parses but does not check" do
    response = App.handle(post("/parse", {"source" => "puts mystery\n"}))
    response.body.should contain "undefined variable mystery"
  end

  it "POST /parse shows a parse error instead of crashing" do
    response = App.handle(post("/parse", {"source" => ")\n"}))
    response.status.should eq 200
    response.body.should contain "Could not parse"
  end

  it "POST /parse refuses oversized source without running the parser" do
    huge = "puts 1\n" * 5_000
    huge.bytesize.should be > CrystalRobots::Web::App::MAX_SOURCE_BYTES
    response = App.handle(post("/parse", {"source" => huge}))
    response.body.should contain "too large"
    response.body.should_not contain "Result"
  end

  it "escapes a pasted robot's source in the textarea, not just inside the fence" do
    response = App.handle(post("/parse", {"source" => "puts \"</textarea><script>\"\n"}))
    response.body.should_not contain "<script>"
    response.body.should contain "&lt;script&gt;"
  end

  it "GET /battle shows a checkbox per example and no result" do
    response = App.handle(request("/battle"))
    response.status.should eq 200
    response.body.should contain %(name="pick_target")
    response.body.should_not contain "Result"
  end

  it "refuses /battle without run capability" do
    App.handle(request("/battle", caps: "oh")).status.should eq 403
  end

  it "POST /battle with fewer than two robots asks for more" do
    response = App.handle(post("/battle", {"pick_target" => "on"}))
    response.body.should contain "Pick two to four robots"
  end

  it "POST /battle runs a seeded match and shows a result table and a Pikchr frame" do
    response = App.handle(post("/battle", {"pick_target" => "on", "pick_rabbit" => "on", "seed" => "7"}))
    response.status.should eq 200
    response.body.should contain "rounds."
    response.body.should contain "| target |"
    response.body.should contain "| rabbit |"
    response.body.should contain "```pikchr"
  end

  it "the same seed reproduces the same battle outcome" do
    params = {"pick_target" => "on", "pick_rabbit" => "on", "seed" => "42"}
    first = App.handle(post("/battle", params)).body
    second = App.handle(post("/battle", params)).body
    first.should eq second
  end

  it "rejects a non-numeric seed instead of crashing" do
    response = App.handle(post("/battle", {"pick_target" => "on", "pick_rabbit" => "on", "seed" => "not-a-number"}))
    response.body.should contain "Seed must be a whole number"
  end

  it "lists saved robots on the overview when the visitor can read wiki pages" do
    response = App.handle(request("/", caps: "oj"))
    response.body.should contain "## Saved robots"
    response.body.should contain "[hunter](/ext/crystal-robots/wiki/hunter)"
  end

  it "hides the saved robots section without wiki-read capability" do
    response = App.handle(request("/", caps: "o"))
    response.body.should_not contain "Saved robots"
  end

  it "shows a saved robot's source and parse derivation" do
    response = App.handle(request("/wiki/hunter", caps: "oj"))
    response.status.should eq 200
    response.body.should contain "hunter (saved robot)"
    response.body.should contain "Parse derivation"
  end

  it "refuses a saved robot without wiki-read capability" do
    App.handle(request("/wiki/hunter", caps: "o")).status.should eq 403
  end

  it "404s an unknown saved robot" do
    App.handle(request("/wiki/nope", caps: "oj")).status.should eq 404
  end

  it "GET /battle lists saved robots as checkboxes when the visitor can read wiki pages" do
    response = App.handle(request("/battle", caps: "oij"))
    response.body.should contain %(name="pick_wiki_hunter")
  end

  it "GET /battle hides saved robots without wiki-read capability" do
    response = App.handle(request("/battle", caps: "oi"))
    response.body.should_not contain "pick_wiki_"
  end

  it "POST /battle runs a match between an example and a saved robot" do
    params = {"pick_target" => "on", "pick_wiki_hunter" => "on", "seed" => "5"}
    response = App.handle(post("/battle", params, caps: "oij"))
    response.status.should eq 200
    response.body.should contain "| target |"
    response.body.should contain "| hunter |"
  end
end
