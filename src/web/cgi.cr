# The Fossil CGI extension. See docs/PLAN.md Phase 5.
#
# `bin/crystal-robots` serves this when Fossil runs it from the extroot
# (`GATEWAY_INTERFACE` is set). Replies are `text/x-markdown`, so Fossil
# wraps them in the repository skin and renders Pikchr fences; the app never
# emits a full HTML page. Identity is `FOSSIL_USER`, permissions are
# `FOSSIL_CAPABILITIES`, both supplied by Fossil.
require "http/params"
require "../compiler"

module CrystalRobots::Web
  # The example robots, embedded at compile time so the CGI needs no
  # filesystem access. Order is the order they are listed.
  EXAMPLES = {
    "counter" => {{ read_file("#{__DIR__}/../../examples/counter.cr") }},
    "rabbit"  => {{ read_file("#{__DIR__}/../../examples/rabbit.cr") }},
    "rook"    => {{ read_file("#{__DIR__}/../../examples/rook.cr") }},
    "sniper"  => {{ read_file("#{__DIR__}/../../examples/sniper.cr") }},
    "target"  => {{ read_file("#{__DIR__}/../../examples/target.cr") }},
    "test"    => {{ read_file("#{__DIR__}/../../examples/test.cr") }},
  }

  class CGI
    getter env : Hash(String, String)

    def initialize(@env : Hash(String, String) = ENV.to_h, @out : IO = STDOUT, @in : IO = STDIN)
    end

    # Links stay inside whatever namespace this binary is served under: the
    # deployed `/ext/robots`, or a session preview at `/ext/preview/<id>`.
    # Fossil prefixes root-relative links in Markdown with the repository
    # root, so the base always starts at `/ext/`.
    def link_base : String
      sn = env["SCRIPT_NAME"]? || ""
      if (i = sn.index("/ext/"))
        sn[i..].rstrip('/')
      else
        "/ext/robots"
      end
    end

    def user : String
      env["FOSSIL_USER"]? || ""
    end

    # Fossil provides the effective capability string; the repository's own
    # anonymous/nobody grants decide what the public may do.
    def capabilities : String
      env["FOSSIL_CAPABILITIES"]? || ""
    end

    # Setup and Admin imply everything; Developer expands to `eoih`, Reader
    # to `oh`. Any one character of `needed` suffices.
    def allowed?(needed : String) : Bool
      caps = capabilities
      return true if caps.includes?('s') || caps.includes?('a')
      effective = caps
      effective += "eoih" if caps.includes?('v')
      effective += "oh" if caps.includes?('u')
      needed.each_char.any? { |c| effective.includes?(c) }
    end

    def path : String
      (env["PATH_INFO"]? || "").strip('/')
    end

    def method : String
      env["REQUEST_METHOD"]? || "GET"
    end

    def query : HTTP::Params
      HTTP::Params.parse(env["QUERY_STRING"]? || "")
    end

    def body : String
      length = (env["CONTENT_LENGTH"]? || "0").to_i? || 0
      return "" if length <= 0
      buffer = Bytes.new(length)
      read = @in.read_fully?(buffer) || 0
      String.new(buffer[0, read])
    end

    def serve : Nil
      return forbidden unless allowed?("oh")
      case path
      when ""
        reply(overview)
      when "version"
        reply("crystal-robots #{CrystalRobots::VERSION}\n")
      when "parse"
        source = method == "POST" ? HTTP::Params.parse(body)["source"]? : query["source"]?
        reply(parse_page(source || ""))
      when /\Aexamples\/([a-z_]+)\z/
        name = $1
        if (src = EXAMPLES[name]?)
          reply(example_page(name, src))
        else
          not_found
        end
      else
        not_found
      end
    end

    def reply(markdown : String, status : String = "200 OK") : Nil
      @out << "Status: " << status << "\r\nContent-Type: text/x-markdown\r\n\r\n" << markdown
    end

    def forbidden : Nil
      @out << "Status: 403 Forbidden\r\nContent-Type: text/html\r\n\r\n"
      @out << "<p>403 Forbidden. <a href=\"/login\">Log in</a> to access this resource.</p>"
    end

    def not_found : Nil
      reply("# Not found\n\nNo such page: `#{path}`. [Back](#{link_base})\n", "404 Not Found")
    end

    def overview : String
      base = link_base
      String.build do |md|
        md << "# Crystal Robots\n\n"
        md << "Write a robot in a small subset of Crystal, watch the compiler turn it into "
        md << "tokens, then a program, then machine code, and battle it on a virtual field. "
        md << "Version `#{CrystalRobots::VERSION}`"
        md << ", logged in as `#{user}`" unless user.empty?
        md << ".\n\n"
        md << "## Example robots\n\n"
        md << "Each page shows the source and the parser's derivation, one line per pass.\n\n"
        EXAMPLES.each_key do |name|
          md << "- [#{name}.cr](#{base}/examples/#{name})\n"
        end
        md << "\n## Parse your own\n\n"
        md << "<form method=\"post\" action=\"#{base}/parse\">\n"
        md << "<textarea name=\"source\" rows=\"12\" cols=\"70\">puts 2 + (1 + 2) // 2 * 4</textarea><br>\n"
        md << "<button type=\"submit\">Parse</button>\n"
        md << "</form>\n\n"
        md << "See [docs/PARSER.md](/doc/trunk/docs/PARSER.md) for how the passes work "
        md << "and [docs/PLAN.md](/doc/trunk/docs/PLAN.md) for what comes next.\n"
      end
    end

    def example_page(name : String, src : String) : String
      String.build do |md|
        md << "# #{name}.cr\n\n[All examples](#{link_base})\n\n"
        md << "```crystal\n" << src << "\n```\n\n"
        md << derivation_section(src)
      end
    end

    def parse_page(source : String) : String
      String.build do |md|
        md << "# Parse\n\n[Back](#{link_base})\n\n"
        if source.strip.empty?
          md << "Nothing to parse.\n"
        else
          md << "```crystal\n" << source << "\n```\n\n"
          md << derivation_section(source)
        end
      end
    end

    # The pass-by-pass derivation, or the parse error with its location.
    def derivation_section(src : String) : String
      String.build do |md|
        md << "## Derivation\n\n"
        begin
          program = Compiler::Parser.new(src).program
          md << "#{program.passes} passes, #{program.size} nodes.\n\n"
          md << "```\n" << program.derivation << "```\n"
        rescue e : Compiler::Parser::Error
          md << "**Parse error:** #{e.message}\n\n"
          program = Compiler::Program.new(src)
          begin
            Compiler::Parser.lex(program)
            while Compiler::Parser.reduce_once(program)
            end
          rescue Compiler::Parser::Error
          end
          md << "```\n" << program.derivation << "```\n" unless program.passes == 0
        end
      end
    end
  end
end
