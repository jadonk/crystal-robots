require "../spec_helper"

alias App = CrystalRobots::Web::App
alias Request = CrystalRobots::Web::Request

private def request(path : String, caps : String = "oi", params = {} of String => String) : Request
  Request.new("GET", path, params, "/ext/crystal-robots", "someone", caps)
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
end
