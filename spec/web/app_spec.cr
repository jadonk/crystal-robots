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
end
