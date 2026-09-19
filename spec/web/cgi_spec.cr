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
end
