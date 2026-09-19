# Saved robots: a wiki page named `robot/<name>` whose Markdown contains
# exactly one fenced code block is that robot's source, the convention
# docs/PLAN.md and the shipped robots/*.md sources both describe. Read
# through the `fossil` CLI's own `wiki list`/`wiki export`, not a direct
# database query -- simpler, at the cost of one subprocess per call
# rather than the single SQL query a later hardening pass could use
# instead.
module CrystalRobots::Web::WikiRobots
  PREFIX = "robot/"

  def self.names : Array(String)
    output = run(["wiki", "list"])
    return [] of String unless output
    output.lines.map(&.strip).select(&.starts_with?(PREFIX)).map { |p| p[PREFIX.size..] }.sort
  end

  # The one fenced code block's contents from a saved robot's wiki page,
  # or `nil` if the page does not exist or has no such block.
  def self.source(name : String) : String?
    output = run(["wiki", "export", "#{PREFIX}#{name}", "-"])
    output.try { |md| extract_fence(md) }
  end

  private def self.extract_fence(markdown : String) : String?
    markdown.match(/```[^\n]*\n(.*?)```/m).try(&.[1])
  end

  # Scrubs the CGI environment variables from the child process, as both
  # GP-Crystal and Ollama-Codex do calling `fossil` from a CGI handler --
  # otherwise Fossil treats the subprocess call itself as a nested CGI
  # request instead of a plain command.
  private def self.run(args : Array(String)) : String?
    out_io = IO::Memory.new
    status = Process.run("fossil", args,
      env: {"GATEWAY_INTERFACE" => nil, "PATH_INFO" => nil, "QUERY_STRING" => nil, "REQUEST_METHOD" => nil},
      output: out_io, error: IO::Memory.new)
    status.success? ? out_io.to_s : nil
  rescue
    nil
  end
end
