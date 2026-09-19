require "./capabilities"
require "./request"
require "./response"
require "./markdown"
require "../compiler/parser"

# The router: one method per route, each returning a `Response` Fossil
# wraps in Markdown chrome. This commit adds `/examples/<name>`; parsing,
# battling and saved robots are later commits.
module CrystalRobots::Web::App
  EXAMPLE_NAME = /\A[A-Za-z0-9_-]+\z/

  def self.handle(req : Request) : Response
    path = req.path
    if path == "" || path == "/"
      overview(req)
    elsif (name = path.lchop?("/examples/"))
      example(req, name)
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
end
