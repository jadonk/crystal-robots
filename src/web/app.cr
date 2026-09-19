require "./capabilities"
require "./request"
require "./response"

# The router: one method per route, each returning a `Response` Fossil
# wraps in Markdown chrome. This commit is the overview alone; `/examples/
# <name>`, parsing, battling and saved robots are later commits.
module CrystalRobots::Web::App
  def self.handle(req : Request) : Response
    case req.path
    when "", "/"
      overview(req)
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
end
