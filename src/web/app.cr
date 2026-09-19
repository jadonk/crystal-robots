require "./capabilities"
require "./request"
require "./response"
require "./markdown"
require "./pikchr"
require "../compiler/parser"
require "../compiler/checker"
require "../battle/field"
require "../battle/match"

# The router: one method per route, each returning a `Response` Fossil
# wraps in Markdown chrome. This commit adds `/battle`; saved robots are
# a later commit.
module CrystalRobots::Web::App
  EXAMPLE_NAME = /\A[A-Za-z0-9_-]+\z/

  # A pasted robot's source is capped well below the parser's own glyph
  # budget (Parser.max_glyphs), so a request that is simply too big is
  # rejected up front with a plain message instead of running the parser
  # at all.
  MAX_SOURCE_BYTES = 20_000

  # A battle runs inside one HTTP request/response, so it needs its own,
  # much smaller limit than the CLI's -l default (500000).
  WEB_CYCLE_LIMIT = 60_000

  def self.handle(req : Request) : Response
    path = req.path
    if path == "" || path == "/"
      overview(req)
    elsif (name = path.lchop?("/examples/"))
      example(req, name)
    elsif path == "/parse"
      parse_page(req)
    elsif path == "/battle"
      battle_page(req)
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

  # GET shows a checkbox per example robot and a seed field; POST runs
  # one seeded match among the checked robots (two to four) up to
  # WEB_CYCLE_LIMIT and shows the outcome as a table plus a Pikchr frame
  # of the final field. Needs run capability (i), the same as parsing.
  private def self.battle_page(req : Request) : Response
    unless Capabilities.can_run?(req.capabilities)
      return Response.new("# Battle\n\nLog in to run a battle.\n", status: 403)
    end

    names = example_names
    picked = req.method == "POST" ? names.select { |n| req.params.has_key?("pick_#{n}") } : [] of String
    seed_text = req.params["seed"]? || ""

    md = String.build do |io|
      io << "# Battle\n\n"
      io << "[back to the overview](" << req.link("/") << ")\n\n"
      io << %(<form method="post" action="#{req.link("/battle")}">\n)
      names.each do |n|
        checked = picked.includes?(n) ? " checked" : ""
        io << %(<label><input type="checkbox" name="pick_#{n}"#{checked}> #{n}</label><br>\n)
      end
      io << %(Seed (optional): <input type="text" name="seed" value="#{html_escape(seed_text)}"><br>\n)
      io << %(<input type="submit" value="Fight">\n)
      io << "</form>\n"

      if req.method == "POST"
        io << "\n## Result\n\n"
        run_battle(io, picked, seed_text)
      end
    end
    Response.new(md)
  end

  private def self.run_battle(io : IO, picked : Array(String), seed_text : String) : Nil
    if picked.size < 2 || picked.size > 4
      io << "Pick two to four robots.\n"
      return
    end
    seed = seed_text.empty? ? nil : seed_text.to_i?
    if !seed_text.empty? && seed.nil?
      io << "Seed must be a whole number.\n"
      return
    end

    programs = picked.map { |n| Compiler::Parser.new(File.read("examples/#{n}.cr")).program }
    field = Battle::Field.new(picked, seed)
    match = Battle::Match.new(field, programs, cycle_limit: WEB_CYCLE_LIMIT)
    match.run

    io << match.rounds << " rounds.\n\n"
    io << "| Robot | Damage | Status |\n|---|---|---|\n"
    field.robots.each { |r| io << "| #{r.name} | #{r.damage}% | #{r.alive? ? "alive" : "dead"} |\n" }

    survivors = field.robots.select(&.alive?)
    io << "\n"
    io << (survivors.size == 1 ? "**#{survivors[0].name} wins!**\n\n" : "No winner.\n\n")
    io << Markdown.fence(Pikchr.field(field), "pikchr")
  end
end
