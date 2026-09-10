# The Fossil CGI extension. See docs/PLAN.md Phase 5.
#
# `bin/crystal-robots` serves this when Fossil runs it from the extroot
# (`GATEWAY_INTERFACE` is set). Replies are `text/x-markdown`, so Fossil
# wraps them in the repository skin and renders Pikchr fences; the app never
# emits a full HTML page. Identity is `FOSSIL_USER`, permissions are
# `FOSSIL_CAPABILITIES`, both supplied by Fossil.
require "http/params"
require "uri"
require "../compiler"
require "../battle/field"

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

    # The full request path for raw HTML attributes (form actions). Fossil
    # rewrites Markdown link targets with the repository prefix, but not
    # attributes inside raw HTML, so those need `SCRIPT_NAME` verbatim.
    def form_base : String
      sn = (env["SCRIPT_NAME"]? || "").rstrip('/')
      sn.includes?("/ext/") ? sn : link_base
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
      when "battle"
        reply(battle_page)
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
        md << "\n## Battle\n\n[Pick robots and fight](#{base}/battle) on the CROBOTS battlefield.\n"
        md << "\n## Parse your own\n\n"
        md << "<form method=\"post\" action=\"#{form_base}/parse\">\n"
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

    WEB_CYCLE_LIMIT = 100_000_i64
    WEB_CYCLE_MAX   = 500_000_i64
    ROBOT_COLORS    = ["0x4C97FF", "0xFF8C1A", "0x59C059", "0xFFAB19"]

    # `GET /battle` without robots shows the form; with `r=` parameters it
    # runs one seeded match and renders a frame of it in Pikchr.
    def battle_page : String
      q = query
      names = q.fetch_all("r").select { |n| EXAMPLES.has_key?(n) }.first(4)
      pasted = (q["src"]? || "").strip
      pasted = "" if pasted.size > PASTE_LIMIT
      return battle_form if names.empty? && pasted.empty?
      seed = (q["seed"]?.try(&.to_u64?) || 1_u64)
      limit = (q["limit"]?.try(&.to_i64?) || WEB_CYCLE_LIMIT).clamp(MOTION_STEP, WEB_CYCLE_MAX)
      entries = names.map { |n| {n, EXAMPLES[n]} }
      entries.unshift({"yours", pasted}) unless pasted.empty?
      entries = entries.first(4)
      entries << entries[0] if entries.size == 1 # CROBOTS clones a lone robot
      field = Battle::Field.new(entries, seed: seed, limit: limit, max_frames: 120)
      field.run
      frame_count = field.frames.size
      frame = (q["frame"]?.try(&.to_i?) || frame_count - 1).clamp(0, frame_count - 1)
      render_battle(field, names, pasted, seed, limit, frame)
    end

    PASTE_LIMIT = 6000

    private MOTION_STEP = Battle::MOTION_CYCLES.to_i64

    def battle_form : String
      String.build do |md|
        md << "# Battle\n\n[Back](#{link_base})\n\n"
        md << "Pick up to four robots. The match is deterministic for a seed, so a result page can be shared and replayed.\n\n"
        md << "<form method=\"get\" action=\"#{form_base}/battle\">\n"
        EXAMPLES.each_key do |name|
          checked = {"counter", "rabbit"}.includes?(name) ? " checked" : ""
          md << "<label><input type=\"checkbox\" name=\"r\" value=\"#{name}\"#{checked}> #{name}</label><br>\n"
        end
        md << "<p>Or paste your own robot (it fights as <b>yours</b>):</p>\n"
        md << "<textarea name=\"src\" rows=\"10\" cols=\"70\" maxlength=\"#{PASTE_LIMIT}\"></textarea><br>\n"
        md << "<label>Seed <input type=\"number\" name=\"seed\" value=\"1\" min=\"0\"></label>\n"
        md << "<label>Cycle limit <input type=\"number\" name=\"limit\" value=\"#{WEB_CYCLE_LIMIT}\" min=\"#{MOTION_STEP}\" max=\"#{WEB_CYCLE_MAX}\"></label>\n"
        md << "<button type=\"submit\">Fight</button>\n</form>\n"
      end
    end

    def battle_link(names : Array(String), pasted : String, seed : UInt64, limit : Int64, frame : Int32) : String
      params = names.map { |n| "r=#{n}" }
      params << "src=#{URI.encode_www_form(pasted)}" unless pasted.empty?
      "#{link_base}/battle?#{params.join("&")}&seed=#{seed}&limit=#{limit}&frame=#{frame}"
    end

    def render_battle(field : Battle::Field, names : Array(String), pasted : String, seed : UInt64, limit : Int64, frame : Int32) : String
      f = field.frames[frame]
      last = field.frames.size - 1
      String.build do |md|
        md << "# Battle: #{field.robots.map(&.name).join(" vs ")}\n\n"
        md << "[Pick again](#{link_base}/battle) · seed #{seed} · limit #{limit} · #{field.cycles} cycles run\n\n"
        if (w = field.winner)
          md << "**Winner: #{w.name}**\n\n"
        elsif field.active.empty?
          md << "**Mutual destruction.**\n\n"
        else
          md << "**Cycle limit reached: #{field.active.map(&.name).join(", ")} survive.**\n\n"
        end
        md << "| Robot | Status | Damage | Instructions | Restarts | Note |\n| --- | --- | --- | --- | --- | --- |\n"
        field.robots.each do |r|
          status = r.error ? "failed" : (r.active ? "active" : "destroyed")
          note = r.error || r.output.first?.try { |line| "puts #{line}" } || ""
          md << "| #{r.name} | #{status} | #{r.damage}% | #{r.cycles} | #{r.restarts} | #{note} |\n"
        end
        md << "\n## Frame #{frame + 1} of #{last + 1} (cycle #{f.cycle})\n\n"
        nav = [] of String
        nav << "[first](#{battle_link(names, pasted, seed, limit, 0)})" if frame > 0
        nav << "[previous](#{battle_link(names, pasted, seed, limit, frame - 1)})" if frame > 0
        nav << "[next](#{battle_link(names, pasted, seed, limit, frame + 1)})" if frame < last
        nav << "[last](#{battle_link(names, pasted, seed, limit, last)})" if frame < last
        md << nav.join(" · ") << "\n\n" unless nav.empty?
        md << "```pikchr\n" << pikchr_frame(f, field.frames[0..frame]) << "```\n\n"
        md << "| Robot | x | y | heading | speed | damage | scan |\n| --- | --- | --- | --- | --- | --- | --- |\n"
        f.robots.each do |r|
          md << "| #{r.name} | #{r.x // Battle::CLICK} | #{r.y // Battle::CLICK} | #{r.heading} | #{r.speed} | #{r.damage}% | #{r.scan} |\n"
        end
        field.robots.each do |r|
          next if r.output.empty?
          md << "\n## #{r.name} output\n\n```\n" << r.output.first(20).join("\n") << "\n```\n"
        end
      end
    end

    # One frame of the field as a Pikchr diagram: 4 inches for 1000 meters,
    # with each robot's trail over the frames so far.
    def pikchr_frame(f : Battle::Frame, history : Array(Battle::Frame) = [f]) : String
      scale = 4.0 / (Battle::MAX_X * Battle::CLICK)
      String.build do |pik|
        pik << "F: box wid 4 ht 4 fill 0xF4F4F0 color 0x888888\n"
        pik << "text \"1000 m\" small at F.n + (0, 0.12)\n"
        f.robots.each_with_index do |r, i|
          points = history.map { |h| h.robots[i] }.map { |s| {(s.x * scale).round(3), (s.y * scale).round(3)} }.uniq
          next if points.size < 2
          color = ROBOT_COLORS[i % ROBOT_COLORS.size]
          pik << "line thin color #{color} from F.sw + (#{points[0][0]}, #{points[0][1]})"
          points[1..].each { |(x, y)| pik << " then to F.sw + (#{x}, #{y})" }
          pik << "\n"
        end
        f.robots.each_with_index do |r, i|
          x = (r.x * scale).round(3)
          y = (r.y * scale).round(3)
          color = r.active ? ROBOT_COLORS[i % ROBOT_COLORS.size] : "0xAAAAAA"
          pik << "R#{i}: circle rad 0.07 fill #{color} color black at F.sw + (#{x}, #{y})\n"
          if r.active
            dx = (0.25 * Battle.lcos(r.heading) / 100000.0).round(3)
            dy = (0.25 * Battle.lsin(r.heading) / 100000.0).round(3)
            pik << "line from R#{i} to R#{i} + (#{dx}, #{dy}) thick color #{color}\n"
          end
          label = r.active ? "#{r.name} #{r.damage}%" : "#{r.name} X"
          pik << "text \"#{label}\" small at R#{i}.n + (0, 0.12)\n"
        end
        f.missiles.each do |m|
          x = (m.x * scale).round(3)
          y = (m.y * scale).round(3)
          if m.exploding
            pik << "circle rad 0.16 thin dashed color red at F.sw + (#{x}, #{y})\n"
          else
            pik << "dot color red at F.sw + (#{x}, #{y})\n"
          end
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
          problems = Compiler::Checker.check(program)
          if problems.empty?
            md << "\nChecks passed: every name is defined and every call has the right number of arguments.\n"
          else
            md << "\n**Problems:**\n\n"
            problems.each { |problem| md << "- #{problem}\n" }
          end
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
