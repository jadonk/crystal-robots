require "./capabilities"
require "./request"
require "./response"
require "./markdown"
require "../compiler/parser"
require "../compiler/checker"

# The router: one method per route, each returning a `Response` Fossil
# wraps in Markdown chrome. This commit adds `/parse`; battling and saved
# robots are later commits.
module CrystalRobots::Web::App
  EXAMPLE_NAME = /\A[A-Za-z0-9_-]+\z/

  # A pasted robot's source is capped well below the parser's own glyph
  # budget (Parser.max_glyphs), so a request that is simply too big is
  # rejected up front with a plain message instead of running the parser
  # at all.
  MAX_SOURCE_BYTES = 20_000

  def self.handle(req : Request) : Response
    path = req.path
    if path == "" || path == "/"
      overview(req)
    elsif (name = path.lchop?("/examples/"))
      example(req, name)
    elsif path == "/parse"
      parse_page(req)
    else
      Response.new("# Not found\n\n#{req.path} is not a page here.\n", status: 404)
    end
  end

  private def self.example_names : Array(String)
    Dir.glob("examples/*.cr").map { |f| File.basename(f, ".cr") }.sort
  end

  private def self.overview(req : Request) : Response
    unless Capabilities.can_read?(req.capabilities)
      return Response.new(<<-MD, status: 403)
        # crystal-robots

        Log in to see the overview.
        MD
    end

    md = String.build do |io|
      io << "# crystal-robots\n\n"
      io << "A small Ruby-like language, compiled to WebAssembly, for CROBOTS-style "
      io << "battle robots.\n\n"
      io << "## Examples\n\n"
      example_names.each do |name|
        io << "- [" << name << "](" << req.link("/examples/#{name}") << ")\n"
      end
    end
    Response.new(md)
  end

  private def self.example(req : Request, name : String) : Response
    unless Capabilities.can_read?(req.capabilities)
      return Response.new("# crystal-robots\n\nLog in to see this example.\n", status: 403)
    end
    unless EXAMPLE_NAME.matches?(name) && File.exists?("examples/#{name}.cr")
      return Response.new("# Not found\n\nNo example named #{Markdown.escape(name)}.\n", status: 404)
    end

    source = File.read("examples/#{name}.cr")
    md = String.build do |io|
      io << "# " << name << "\n\n"
      io << "[back to the overview](" << req.link("/") << ")\n\n"
      io << "## Source\n\n"
      io << Markdown.fence(source, "crystal")
      io << "\n## Parse derivation\n\n"
      begin
        program = Compiler::Parser.new(source).program
        io << Markdown.fence(program.derivation)
      rescue e : Compiler::Parser::Error
        io << "Could not parse: " << Markdown.escape(e.message || "unknown error") << "\n"
      end
    end
    Response.new(md)
  end

  # GET shows the paste form empty; POST parses, checks and shows the
  # derivation and any issues. Needs run capability (i): parsing arbitrary
  # pasted text, unlike reading a file already in the repository, is work
  # done on the visitor's behalf and gated the same as running one.
  private def self.parse_page(req : Request) : Response
    unless Capabilities.can_run?(req.capabilities)
      return Response.new("# Parse a robot\n\nLog in to parse a robot.\n", status: 403)
    end

    source = req.method == "POST" ? req.params["source"]? : nil
    md = String.build do |io|
      io << "# Parse a robot\n\n"
      io << "[back to the overview](" << req.link("/") << ")\n\n"
      io << %(<form method="post" action="#{req.link("/parse")}">\n)
      io << %(<textarea name="source" rows="20" cols="80">) << html_escape(source || "") << "</textarea><br>\n"
      io << %(<input type="submit" value="Parse">\n)
      io << "</form>\n"

      if source && source.bytesize > MAX_SOURCE_BYTES
        io << "\nThat source is too large (over #{MAX_SOURCE_BYTES} bytes); trim it and try again.\n"
      elsif source
        io << "\n## Result\n\n"
        begin
          program = Compiler::Parser.new(source).program
          io << Markdown.fence(program.derivation)
          issues = Compiler::Checker.check(program)
          if issues.empty?
            io << "\nNo issues found.\n"
          else
            io << "\n### Checker issues\n\n"
            issues.each { |issue| io << "- " << Markdown.escape(issue.to_s) << "\n" }
          end
        rescue e : Compiler::Parser::Error
          io << "Could not parse: " << Markdown.escape(e.message || "unknown error") << "\n"
        end
      end
    end
    Response.new(md)
  end

  private def self.html_escape(text : String) : String
    text.gsub(/[&<>"]/) { |c| {"&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;"}[c] }
  end
end
