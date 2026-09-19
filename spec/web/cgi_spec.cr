require "../spec_helper"

# An integration spec, not a unit spec: runs the actual `crystal-robots`
# entry point the way Fossil's CGI extension mechanism does -- as a
# subprocess with the standard CGI environment variables set and its
# stdout captured -- rather than calling `Web::App` directly.
private def cgi_get(path : String, script_name = "/ext/crystal-robots", caps = "oh") : String
  env = {
    "GATEWAY_INTERFACE"   => "CGI/1.1",
    "REQUEST_METHOD"      => "GET",
    "PATH_INFO"           => path,
    "SCRIPT_NAME"         => script_name,
    "QUERY_STRING"        => "",
    "FOSSIL_USER"         => "someone",
    "FOSSIL_CAPABILITIES" => caps,
  }
  io = IO::Memory.new
  Process.run("crystal", ["run", "src/cli.cr"], env: env, output: io, error: STDERR)
  io.to_s
end

private def cgi_post(path : String, body : String, script_name = "/ext/crystal-robots", caps = "oi") : String
  env = {
    "GATEWAY_INTERFACE"   => "CGI/1.1",
    "REQUEST_METHOD"      => "POST",
    "PATH_INFO"           => path,
    "SCRIPT_NAME"         => script_name,
    "CONTENT_LENGTH"      => body.bytesize.to_s,
    "FOSSIL_USER"         => "someone",
    "FOSSIL_CAPABILITIES" => caps,
  }
  out_io = IO::Memory.new
  Process.run("crystal", ["run", "src/cli.cr"], env: env, input: IO::Memory.new(body), output: out_io, error: STDERR)
  out_io.to_s
end

describe "the CGI entry point" do
  it "serves the overview with a Content-Type header and the examples list" do
    output = cgi_get("/")
    output.should start_with "Content-Type: text/x-markdown\r\n\r\n"
    output.should contain "# crystal-robots"
    output.should contain "examples/hello"
  end

  it "answers 403 without read capability" do
    output = cgi_get("/", caps: "")
    output.should start_with "Status: 403\r\n"
  end

  it "answers 404 for an unknown path" do
    output = cgi_get("/nope")
    output.should start_with "Status: 404\r\n"
  end

  it "serves an example's source and derivation" do
    output = cgi_get("/examples/hello")
    output.should contain "puts 42"
    output.should contain "Parse derivation"
  end

  it "POST /parse parses a pasted robot's body and reports no issues" do
    output = cgi_post("/parse", "source=puts+1")
    output.should contain "No issues found"
  end

  it "POST /battle runs a real seeded match end to end" do
    output = cgi_post("/battle", "pick_target=on&pick_rabbit=on&seed=3")
    output.should contain "rounds."
    output.should contain "```pikchr"
  end

  it "serves a saved robot's source from the repository's wiki pages" do
    output = cgi_get("/wiki/hunter", caps: "oj")
    output.should contain "hunter (saved robot)"
    output.should contain "Parse derivation"
  end

  it "POST /battle runs a match between an example and a saved robot" do
    output = cgi_post("/battle", "pick_target=on&pick_wiki_hunter=on&seed=5", caps: "oij")
    output.should contain "| target |"
    output.should contain "| hunter |"
  end

  it "refuses an oversized request body before allocating anything" do
    env = {
      "GATEWAY_INTERFACE" => "CGI/1.1", "REQUEST_METHOD" => "POST", "PATH_INFO" => "/parse",
      "SCRIPT_NAME" => "/ext/crystal-robots", "CONTENT_LENGTH" => "999999999",
      "FOSSIL_USER" => "someone", "FOSSIL_CAPABILITIES" => "oi",
    }
    out_io = IO::Memory.new
    Process.run("crystal", ["run", "src/cli.cr"], env: env, input: IO::Memory.new(""), output: out_io, error: STDERR)
    out_io.to_s.should start_with "Status: 400\r\n"
  end
end
