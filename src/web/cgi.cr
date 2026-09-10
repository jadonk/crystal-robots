# The Fossil CGI extension. See docs/PLAN.md Phase 5.
#
# `bin/crystal-robots` serves this when Fossil runs it from the extroot
# (`GATEWAY_INTERFACE` is set). Replies are `text/x-markdown`, so Fossil
# wraps them in the repository skin and renders Pikchr fences; the app never
# emits a full HTML page. Identity is `FOSSIL_USER`, permissions are
# `FOSSIL_CAPABILITIES`, both supplied by Fossil.
require "http/params"
require "html"
require "uri"
require "../compiler"
require "../battle/field"

module CrystalRobots::Web
  # The example robots, embedded at compile time so the CGI needs no
  # filesystem access. The list is whatever `examples/*.cr` holds when the
  # binary is built, in name order.
  EXAMPLES = {% begin %}
    {
      {% for file in `ls examples/*.cr`.split.sort %}
        {{ file.split("/").last.gsub(/\.cr$/, "") }} => {{ read_file(file) }},
      {% end %}
    }
  {% end %}

  # Robots saved as Fossil wiki pages. A page named `robot/<name>` holds
  # Markdown with exactly one fenced code block, which is the robot source.
  # Pages are read through the fossil binary with the CGI variables
  # scrubbed, so fossil does not mistake the call for a CGI request.
  class WikiRobots
    PREFIX = "robot/"
    FENCE  = /^(`{3,})[^\n]*\n(.*?)\n\1[ \t]*$/m
    # Names are what shows in headings, links and labels; keep them plain.
    NAME = /\A[A-Za-z0-9][A-Za-z0-9 _.-]{0,39}\z/

    alias Lister = -> Array(String)
    alias Reader = String -> String?

    getter names : Array(String)

    def initialize(@list : Lister, @read : Reader, @limit : Int32 = 20_000)
      @names = @list.call.select(&.starts_with?(PREFIX)).map { |page| page[PREFIX.size..] }.select { |n| n =~ NAME }.sort
    end

    # The deployed repository, if Fossil told us where it is.
    def self.for_repository(repository : String?) : WikiRobots
      if repository && File.exists?(repository)
        new(-> { fossil(["wiki", "list", "-R", repository]).lines.map(&.strip) },
          ->(name : String) : String? { fossil(["wiki", "export", PREFIX + name, "-R", repository]) })
      else
        new(-> { [] of String }, ->(name : String) : String? { nil })
      end
    end

    # The first paragraph of the page before its code block, for listings.
    def description(name : String) : String
      return "" unless @names.includes?(name)
      page = @read.call(name) || ""
      body = page.split(/^`{3,}/m, 2)[0]
      paragraph = body.split(/\n[ \t]*\n/).map(&.strip).find { |para| !para.empty? && !para.starts_with?("#") } || ""
      text = paragraph.gsub(/\s+/, " ")
      text.size > 160 ? text[0, 157] + "..." : text
    end

    # The source of the robot, or nil if the page has no single fence or the
    # fence is larger than a pasted robot may be.
    def source(name : String) : String?
      return nil unless @names.includes?(name)
      page = @read.call(name)
      return nil unless page
      fences = page.scan(FENCE)
      return nil unless fences.size == 1
      src = fences[0][2]
      src.size <= @limit ? src : nil
    end

    private def self.fossil(args : Array(String)) : String
      output = IO::Memory.new
      scrub = {"GATEWAY_INTERFACE" => nil, "PATH_INFO" => nil, "QUERY_STRING" => nil, "REQUEST_METHOD" => nil,
               "CONTENT_LENGTH" => nil, "SCRIPT_NAME" => nil, "HTTP_COOKIE" => nil}
      Process.run("fossil", args, env: scrub, output: output, error: Process::Redirect::Close)
      output.to_s
    end
  end

  class CGI
    getter env : Hash(String, String)
    property wiki : WikiRobots { WikiRobots.for_repository(env["FOSSIL_REPOSITORY"]?) }

    # Saved robots are wiki pages, so seeing them needs Fossil's wiki-read
    # capability (`j`); Setup and Admin imply it.
    def wiki_visible? : Bool
      allowed?("j")
    end

    # A Pikchr string literal: quotes and backslashes escaped, length kept sane.
    def pikchr_text(text : String) : String
      text[0, 40].gsub('\\', "\\\\").gsub('"', "\\\"")
    end

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
        "/ext/crystal-robots"
      end
    end

    # Request bounds: the body is capped before it is allocated, sources are
    # capped by length before parsing and by the parser's glyph budget during
    # it (flat robots parse in milliseconds; a pathological operator chain
    # hits the budget instead of the square of its length), and a battle is
    # capped by its cycle limit (a 500k-cycle match of four robots takes
    # about four seconds). Parse and battle also need a real login.
    BODY_LIMIT   = 65_536
    SOURCE_LIMIT = 20_000
    PASTE_LIMIT  =  6_000 # a pasted robot travels in the battle page's links

    class BadRequest < Exception
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

    # Fossil's anonymous and nobody logins do not count. Parsing and
    # battling are for named users until the parser's worst cases are
    # bounded well enough to open them up.
    def logged_in? : Bool
      !user.empty? && !{"anonymous", "nobody"}.includes?(user)
    end

    # Fossil's login page returns to `g` afterwards.
    def login_link(back : String = form_base + "/" + path) : String
      "/login?g=#{URI.encode_www_form(back)}"
    end

    def login_required : Nil
      reply("# Log in first\n\nParsing and battles are available to logged-in users. [Log in](#{login_link}) to continue, or return to the [overview](#{link_base}).\n", "403 Forbidden")
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
      effective += "eoihj" if caps.includes?('v')
      effective += "ohj" if caps.includes?('u')
      needed.each_char.any? { |c| effective.includes?(c) }
    end

    def path : String
      (env["PATH_INFO"]? || "").strip('/')
    end

    def method : String
      env["REQUEST_METHOD"]? || "GET"
    end

    def query : HTTP::Params
      HTTP::Params.parse(utf8!(env["QUERY_STRING"]?) || "")
    end

    def body : String
      length = (env["CONTENT_LENGTH"]? || "0").to_i? || 0
      return "" if length <= 0
      raise BadRequest.new("request body larger than #{BODY_LIMIT} bytes") if length > BODY_LIMIT
      buffer = Bytes.new(length)
      read = @in.read_fully?(buffer) || 0
      text = String.new(buffer[0, read])
      raise BadRequest.new("request body is not valid UTF-8") unless text.valid_encoding?
      text
    end

    # Query and form values must be valid UTF-8 before anything looks at them.
    private def utf8!(value : String?) : String?
      return value if value.nil? || value.valid_encoding?
      raise BadRequest.new("request is not valid UTF-8")
    end

    # Every request gets a reply: 400 for bad input, 500 for anything else.
    def serve : Nil
      route
    rescue e : BadRequest
      plain("400 Bad Request", "400 Bad Request: #{e.message}")
    rescue e
      plain("500 Internal Server Error", "500 Internal Server Error: #{e.class}: #{e.message}")
    end

    def route : Nil
      return forbidden unless allowed?("oh")
      raise BadRequest.new("path is not valid UTF-8") unless path.valid_encoding?
      case path
      when ""
        reply(overview)
      when "version"
        reply("crystal-robots #{CrystalRobots::VERSION}\n")
      when "parse"
        return login_required unless logged_in?
        source = method == "POST" ? HTTP::Params.parse(body)["source"]? : nil
        reply(parse_page(source || ""))
      when "battle"
        return login_required unless logged_in?
        reply(battle_page)
      when /\Aexamples\/([a-z_]+)\z/
        name = $1
        if (src = EXAMPLES[name]?)
          reply(example_page(name, src))
        else
          not_found
        end
      when /\Awiki\/(.+)\z/
        return login_required unless logged_in?
        return forbidden unless wiki_visible?
        name = URI.decode($1)
        if (src = wiki.source(name))
          reply(wiki_page(name, src))
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

    def plain(status : String, text : String) : Nil
      @out << "Status: " << status << "\r\nContent-Type: text/plain\r\n\r\n" << text << "\n"
    end

    def not_found : Nil
      reply("# Not found\n\nNo such page: #{inline(path)}. [Back](#{link_base})\n", "404 Not Found")
    end

    # User text inside Markdown prose or a table cell: HTML-escaped, with
    # the characters that would start markup or split a table neutralized.
    def inline(text : String) : String
      HTML.escape(text).gsub('|', "&#124;").gsub('`', "&#96;").gsub('*', "&#42;").gsub('_', "&#95;").gsub('[', "&#91;")
    end

    # User text inside a code fence: the fence is longer than any run of
    # backticks in the text, so the text cannot close it.
    def fenced(text : String, info : String = "") : String
      longest = text.scan(/`+/).max_of? { |m| m[0].size } || 0
      fence = "`" * Math.max(3, longest + 1)
      "#{fence}#{info}\n#{text.chomp}\n#{fence}\n"
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
        if wiki_visible?
          md << "\n## Saved robots\n\n"
          if wiki.names.empty?
            md << "None yet. Create a wiki page named `robot/<name>` whose Markdown holds exactly one code block, and it appears here and in the battle picker.\n"
          else
            md << "Wiki pages named `robot/<name>` whose one code block is the robot. "
            md << "Add your own the same way, or [write one from a template](/wikiedit?name=#{URI.encode_www_form(WikiRobots::PREFIX + "mine")}).\n\n"
            md << "| Robot | What it does | |\n| --- | --- | --- |\n"
            wiki.names.each do |name|
              view = "#{base}/wiki/#{URI.encode_path_segment(name)}"
              page = "/wiki?name=#{URI.encode_www_form(WikiRobots::PREFIX + name)}"
              fight = "#{base}/battle?pick=#{URI.encode_www_form(name)}"
              md << "| [#{inline(name)}](#{view}) | #{inline(wiki.description(name))} | [page](#{page}) · [fight](#{fight}) |\n"
            end
          end
        end
        if logged_in?
          md << "\n## Battle\n\n[Pick robots and fight](#{base}/battle) on the CROBOTS battlefield.\n"
          md << "\n## Parse your own\n\n"
          md << "<form method=\"post\" action=\"#{form_base}/parse\">\n"
          md << "<textarea name=\"source\" rows=\"12\" cols=\"70\">puts 2 + (1 + 2) // 2 * 4</textarea><br>\n"
          md << "<button type=\"submit\">Parse</button>\n"
          md << "</form>\n\n"
        else
          md << "\n## Battle and parse\n\nRunning battles and parsing your own robots needs a login: [log in](#{login_link(form_base)}) and this page will offer both.\n\n"
        end
        md << "See [docs/PARSER.md](/doc/trunk/docs/PARSER.md) for how the passes work "
        md << "and [docs/PLAN.md](/doc/trunk/docs/PLAN.md) for what comes next.\n"
      end
    end

    def example_page(name : String, src : String) : String
      String.build do |md|
        md << "# #{inline(name)}\n\n[All examples](#{link_base})\n\n"
        md << fenced(src, "crystal") << "\n"
        md << derivation_section(src)
      end
    end

    def wiki_page(name : String, src : String) : String
      String.build do |md|
        page = "/wiki?name=#{URI.encode_www_form(WikiRobots::PREFIX + name)}"
        edit = "/wikiedit?name=#{URI.encode_www_form(WikiRobots::PREFIX + name)}"
        fight = "#{link_base}/battle?w=#{URI.encode_www_form(name)}&r=counter&r=rabbit"
        md << "# #{inline(name)}\n\n"
        md << "Saved robot from the wiki page [#{inline(WikiRobots::PREFIX + name)}](#{page}) ([edit](#{edit})). "
        md << "[Fight it against counter and rabbit](#{fight}) or [pick opponents](#{link_base}/battle?pick=#{URI.encode_www_form(name)}). [All robots](#{link_base})\n\n"
        description = wiki.description(name)
        md << inline(description) << "\n\n" unless description.empty?
        md << fenced(src, "crystal") << "\n"
        md << derivation_section(src)
      end
    end

    def parse_page(source : String) : String
      String.build do |md|
        md << "# Parse\n\n[Back](#{link_base})\n\n"
        if source.strip.empty?
          md << "Nothing to parse. Use the form on the [overview](#{link_base}).\n"
        elsif source.size > SOURCE_LIMIT
          md << "That is #{source.size} characters; the limit is #{SOURCE_LIMIT}.\n"
        else
          md << fenced(source, "crystal") << "\n"
          md << derivation_section(source)
        end
      end
    end

    WEB_CYCLE_LIMIT =  60_000_i64 # about three minutes of replay at the default pace
    WEB_CYCLE_MAX   = 500_000_i64
    ROBOT_COLORS    = ["0x4C97FF", "0xFF8C1A", "0x59C059", "0xFFAB19"]
    ANIM_FRAMES     = 400 # keyframes recorded per match; SMIL interpolates between them
    # Replay pace in CROBOTS cycles per second (`cps=`). At 300 a motion
    # update lands every 50 ms: a robot at full speed crosses the field in
    # about seven seconds and a missile covers its 700 m range in under a
    # second, which is the feel of the original curses display.
    ANIM_CPS     =    300
    ANIM_CPS_MAX = 20_000
    # A series like `crobots -m`: seeds seed, seed+1, ... with a total work cap.
    MATCHES_MAX      =          10
    SERIES_CYCLE_MAX = 600_000_i64

    # `GET /battle` without robots shows the form; with `r=` parameters it
    # runs one seeded match and renders a frame of it in Pikchr.
    def battle_page : String
      q = query
      names = q.fetch_all("r").select { |n| EXAMPLES.has_key?(n) }.first(4)
      saved = wiki_visible? ? q.fetch_all("w").select { |n| wiki.names.includes?(n) }.first(4) : [] of String
      pasted = (q["src"]? || "").strip
      pasted = "" if pasted.size > PASTE_LIMIT
      return battle_form(q.fetch_all("pick")) if names.empty? && saved.empty? && pasted.empty?
      seed = (q["seed"]?.try(&.to_u64?) || 1_u64)
      limit = (q["limit"]?.try(&.to_i64?) || WEB_CYCLE_LIMIT).clamp(MOTION_STEP, WEB_CYCLE_MAX)
      entries = names.map { |n| {n, EXAMPLES[n]} }
      saved.each { |n| entries << {n, wiki.source(n) || "# robot/#{n} has no single code block\n"} }
      entries.unshift({"yours", pasted}) unless pasted.empty?
      entries = entries.first(4)
      entries << entries[0] if entries.size == 1 # CROBOTS clones a lone robot
      matches = (q["matches"]?.try(&.to_i?) || 1).clamp(1, MATCHES_MAX)
      if matches > 1
        allowed = Math.min(matches, (SERIES_CYCLE_MAX // limit).to_i32).clamp(1, MATCHES_MAX)
        return series_page(entries, names, saved, pasted, seed, limit, allowed, matches - allowed)
      end
      field = Battle::Field.new(entries, seed: seed, limit: limit, max_frames: ANIM_FRAMES)
      field.run
      frame_count = field.frames.size
      frame = (q["frame"]?.try(&.to_i?) || frame_count - 1).clamp(0, frame_count - 1)
      cps = (q["cps"]?.try(&.to_i?) || ANIM_CPS).clamp(1, ANIM_CPS_MAX)
      render_battle(field, names, pasted, seed, limit, frame, cps, saved)
    end

    private MOTION_STEP = Battle::MOTION_CYCLES.to_i64

    # `picked` are saved robots to pre-check (from `pick=` links).
    def battle_form(picked : Array(String) = [] of String) : String
      String.build do |md|
        md << "# Battle\n\n[Back](#{link_base})\n\n"
        md << "Pick up to four robots. The match is deterministic for a seed, so a result page can be shared and replayed.\n\n"
        md << "<form method=\"get\" action=\"#{form_base}/battle\">\n"
        md << "<p>Built-in examples:</p>\n"
        EXAMPLES.each_key do |name|
          checked = picked.empty? && {"counter", "rabbit"}.includes?(name) ? " checked" : ""
          md << "<label><input type=\"checkbox\" name=\"r\" value=\"#{name}\"#{checked}> #{name}</label> "
          md << "<a href=\"#{form_base}/examples/#{name}\">view</a><br>\n"
        end
        if wiki_visible? && !wiki.names.empty?
          md << "<p>Saved robots (wiki pages <code>robot/&lt;name&gt;</code>):</p>\n"
          wiki.names.each do |name|
            checked = picked.includes?(name) ? " checked" : ""
            md << "<label><input type=\"checkbox\" name=\"w\" value=\"#{HTML.escape(name)}\"#{checked}> #{HTML.escape(name)}</label> "
            md << "<a href=\"#{form_base}/wiki/#{URI.encode_path_segment(name)}\">view</a><br>\n"
          end
          md << "<p>Picked a saved robot with nothing to fight? Check an example too, or it fights a copy of itself.</p>\n" unless picked.empty?
        end
        md << "<p>Or paste your own robot (it fights as <b>yours</b>):</p>\n"
        md << "<textarea name=\"src\" rows=\"10\" cols=\"70\" maxlength=\"#{PASTE_LIMIT}\"></textarea><br>\n"
        md << "<label>Seed <input type=\"number\" name=\"seed\" value=\"1\" min=\"0\"></label>\n"
        md << "<label>Cycle limit <input type=\"number\" name=\"limit\" value=\"#{WEB_CYCLE_LIMIT}\" min=\"#{MOTION_STEP}\" max=\"#{WEB_CYCLE_MAX}\"></label>\n"
        md << "<label>Replay speed, cycles per second <input type=\"number\" name=\"cps\" value=\"#{ANIM_CPS}\" min=\"1\" max=\"#{ANIM_CPS_MAX}\"></label>\n"
        md << "<label>Matches <input type=\"number\" name=\"matches\" value=\"1\" min=\"1\" max=\"#{MATCHES_MAX}\"></label> (more than one gives a score table like <code>crobots -m</code>, seeds counting up from the seed)\n"
        md << "<button type=\"submit\">Fight</button>\n</form>\n"
      end
    end

    def battle_link(names : Array(String), pasted : String, seed : UInt64, limit : Int64, frame : Int32, cps : Int32 = ANIM_CPS, saved : Array(String) = [] of String) : String
      params = names.map { |n| "r=#{n}" }
      saved.each { |n| params << "w=#{URI.encode_www_form(n)}" }
      params << "src=#{URI.encode_www_form(pasted)}" unless pasted.empty?
      "#{link_base}/battle?#{params.join("&")}&seed=#{seed}&limit=#{limit}&cps=#{cps}&frame=#{frame}"
    end

    def render_battle(field : Battle::Field, names : Array(String), pasted : String, seed : UInt64, limit : Int64, frame : Int32, cps : Int32 = ANIM_CPS, saved : Array(String) = [] of String) : String
      f = field.frames[frame]
      last = field.frames.size - 1
      seconds = (field.cycles.to_f / cps).round(1)
      String.build do |md|
        md << "# Battle: #{field.robots.map { |r| inline(r.name) }.join(" vs ")}\n\n"
        md << "[Pick again](#{link_base}/battle) · seed #{seed} · limit #{limit} · #{field.cycles} cycles run · "
        md << "replay at #{cps} cycles per second (#{seconds} s), looping\n\n"
        md << svg_animation(field, cps) << "\n\n"
        md << "## Frame #{frame + 1} of #{last + 1} (cycle #{f.cycle})\n\n"
        nav = [] of String
        nav << "[first](#{battle_link(names, pasted, seed, limit, 0, cps, saved)})" if frame > 0
        nav << "[previous](#{battle_link(names, pasted, seed, limit, frame - 1, cps, saved)})" if frame > 0
        nav << "[next](#{battle_link(names, pasted, seed, limit, frame + 1, cps, saved)})" if frame < last
        nav << "[last](#{battle_link(names, pasted, seed, limit, last, cps, saved)})" if frame < last
        md << nav.join(" · ") << "\n\n" unless nav.empty?
        md << "```pikchr\n" << pikchr_frame(f, field.frames[0..frame]) << "```\n\n"
        md << "| Robot | x | y | heading | speed | damage | scan | cannon |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n"
        f.robots.each do |r|
          md << "| #{inline(r.name)} | #{r.x // Battle::CLICK} | #{r.y // Battle::CLICK} | #{r.heading} | #{r.speed} | #{r.damage}% | #{r.scan} | #{r.fired ? r.cannon : "-"} |\n"
        end
        md << "\n## Result\n\n"
        if (w = field.winner)
          md << "**Winner: #{inline(w.name)}**\n\n"
        elsif field.active.empty?
          md << "**Mutual destruction.**\n\n"
        else
          md << "**Cycle limit reached: #{field.active.map { |r| inline(r.name) }.join(", ")} survive.**\n\n"
        end
        md << "| Robot | Status | Damage | Instructions | Restarts | Note |\n| --- | --- | --- | --- | --- | --- |\n"
        field.robots.each do |r|
          status = r.error ? "failed" : (r.active ? "active" : "destroyed")
          note = r.error || r.output.first?.try { |line| "puts #{line}" } || ""
          md << "| #{inline(r.name)} | #{status} | #{r.damage}% | #{r.cycles} | #{r.restarts} | #{inline(note)} |\n"
        end
        field.robots.each do |r|
          next if r.output.empty?
          md << "\n## #{inline(r.name)} output\n\n" << fenced(r.output.first(20).join("\n"))
        end
      end
    end

    # `crobots -m`: several seeded matches and a cumulative score, each
    # match linking to its own replay.
    def series_page(entries : Array({String, String}), names : Array(String), saved : Array(String), pasted : String, seed : UInt64, limit : Int64, matches : Int32, trimmed : Int32 = 0) : String
      wins = Array(Int32).new(entries.size, 0)
      ties = Array(Int32).new(entries.size, 0)
      rows = [] of String
      matches.times do |m|
        s = seed + m
        field = Battle::Field.new(entries, seed: s, limit: limit, max_frames: 2)
        field.run
        survivors = field.active
        field.robots.each_with_index do |r, i|
          next unless r.active
          survivors.size == 1 ? (wins[i] += 1) : (ties[i] += 1)
        end
        outcome = if (w = field.winner)
                    "#{inline(w.name)} wins"
                  elsif survivors.empty?
                    "mutual destruction"
                  else
                    "limit: #{survivors.map { |r| inline(r.name) }.join(", ")} survive"
                  end
        damage = field.robots.map { |r| "#{inline(r.name)} #{r.error ? "failed" : "#{r.damage}%"}" }.join(", ")
        replay = battle_link(names, pasted, s, limit, 0, ANIM_CPS, saved)
        rows << "| #{m + 1} | #{s} | #{field.cycles} | #{outcome} | #{damage} | [replay](#{replay}) |"
      end
      String.build do |md|
        md << "# Series: #{entries.map { |(n, _)| inline(n) }.join(" vs ")}\n\n"
        md << "[Pick again](#{link_base}/battle) · #{matches} matches · seeds #{seed} to #{seed + matches - 1} · limit #{limit} cycles each"
        md << " · #{trimmed} more dropped to keep the series under #{SERIES_CYCLE_MAX} cycles; lower the limit for more matches" if trimmed > 0
        md << "\n\n"
        md << "## Score\n\n| Robot | Wins | Ties |\n| --- | --- | --- |\n"
        entries.each_with_index { |(n, _), i| md << "| #{inline(n)} | #{wins[i]} | #{ties[i]} |\n" }
        md << "\n## Matches\n\n| # | Seed | Cycles | Outcome | Damage | |\n| --- | --- | --- | --- | --- | --- |\n"
        rows.each { |row| md << row << "\n" }
      end
    end

    # The whole match as one SVG with native (SMIL) animation: no script,
    # so it works under Fossil's content security policy. Positions are
    # keyframes at each recorded frame, interpolated linearly in between;
    # missiles switch discretely. Fossil passes raw HTML blocks through.
    def svg_animation(field : Battle::Field, cps : Int32 = ANIM_CPS) : String
      frames = field.frames
      total = Math.max(1_i64, frames.last.cycle)
      # screen time is proportional to cycles, so the pace is a fixed number
      # of CROBOTS cycles per second however many frames were recorded
      key_times = frames.map { |f| (f.cycle.to_f / total).round(5) }.join(';')
      dur = "#{(total.to_f / cps).round(3)}s"
      String.build do |svg|
        svg << %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="-30 -30 1060 1060" width="520" height="520" role="img" aria-label="battle replay">\n)
        svg << %(<rect x="0" y="0" width="1000" height="1000" fill="#f4f4f0" stroke="#888" stroke-width="3"/>\n)
        field.robots.each_with_index do |robot, i|
          color = "#" + ROBOT_COLORS[i % ROBOT_COLORS.size][2..]
          xs = frames.map { |f| f.robots[i].x // Battle::CLICK }
          ys = frames.map { |f| 1000 - f.robots[i].y // Battle::CLICK }
          alive = frames.map { |f| f.robots[i].active ? "1" : "0.3" }
          # the trail is drawn as far as the robot has come: a dashed stroke
          # whose visible length follows the path length at each frame
          lengths = [0.0]
          xs.each_index { |k| next if k == 0; lengths << lengths[k - 1] + Math.hypot(xs[k] - xs[k - 1], ys[k] - ys[k - 1]) }
          total = Math.max(1.0, lengths.last)
          svg << %(<polyline fill="none" stroke="#{color}" stroke-opacity="0.35" stroke-width="3" stroke-dasharray="#{total.round(1)}" points=")
          xs.each_with_index { |x, k| svg << x << ',' << ys[k] << ' ' }
          svg << %(">\n)
          svg << animate("stroke-dashoffset", lengths.map { |l| (total - l).round(1) }.join(';'), key_times, dur, "linear")
          svg << "</polyline>\n"
          # the robot: one group translated along the path; inside it the
          # body, the nose (drive heading), the scanner sweep and the cannon
          # barrel rotate about the centre. Screen y points down, so a
          # heading of h degrees is a rotation of -h.
          svg << %(<g>\n)
          svg << animate_transform("translate", xs.each_with_index.map { |x, k| "#{x} #{ys[k]}" }.join(';'), key_times, dur, "linear")
          svg << animate("opacity", alive.join(';'), key_times, dur, "discrete")
          scans = frames.map { |f| -f.robots[i].scan }
          svg << %(<line x1="0" y1="0" x2="160" y2="0" stroke="#{color}" stroke-opacity="0.45" stroke-width="2" stroke-dasharray="6 6">\n)
          svg << animate_transform("rotate", scans.join(';'), key_times, dur, "discrete")
          svg << "</line>\n"
          svg << %(<circle r="14" fill="#{color}" stroke="#000" stroke-width="2"/>\n)
          headings = unwrap(frames.map { |f| -f.robots[i].heading })
          svg << %(<line x1="0" y1="0" x2="30" y2="0" stroke="#000" stroke-width="4" stroke-linecap="round">\n)
          svg << animate_transform("rotate", headings.join(';'), key_times, dur, "linear")
          svg << "</line>\n"
          cannons = frames.map { |f| -f.robots[i].cannon }
          shown = frames.map { |f| f.robots[i].fired ? "1" : "0" }
          svg << %(<line x1="0" y1="0" x2="26" y2="0" stroke="#d00" stroke-width="6" stroke-linecap="butt">\n)
          svg << animate_transform("rotate", cannons.join(';'), key_times, dur, "discrete")
          svg << animate("opacity", shown.join(';'), key_times, dur, "discrete")
          svg << "</line>\n"
          svg << %(<text y="-24" font-size="30" font-family="sans-serif" text-anchor="middle" fill="#222">#{HTML.escape(robot.name)}</text>\n)
          svg << "</g>\n"
        end
        field.robots.each_index do |owner|
          Battle::MIS_ROBOT.times do |slot|
            xs = [] of Int32
            ys = [] of Int32
            rs = [] of Int32
            ops = [] of String
            last_x = 0
            last_y = 0
            frames.each do |f|
              m = f.missiles.find { |st| st.owner == owner && st.slot == slot }
              if m
                last_x = m.x // Battle::CLICK
                last_y = 1000 - m.y // Battle::CLICK
                rs << (m.exploding ? 40 : 7)
                ops << (m.exploding ? "0.25" : "1")
              else
                rs << 0
                ops << "0"
              end
              xs << last_x
              ys << last_y
            end
            next if rs.all?(&.zero?)
            svg << %(<circle r="0" fill="#d00" stroke="#d00" stroke-width="2">\n)
            svg << animate("cx", xs.join(';'), key_times, dur, "discrete")
            svg << animate("cy", ys.join(';'), key_times, dur, "discrete")
            svg << animate("r", rs.join(';'), key_times, dur, "discrete")
            svg << animate("fill-opacity", ops.join(';'), key_times, dur, "discrete")
            svg << "</circle>\n"
          end
        end
        svg << "</svg>"
      end
    end

    private def animate(attr : String, values : String, key_times : String, dur : String, mode : String) : String
      %(<animate attributeName="#{attr}" values="#{values}" keyTimes="#{key_times}" dur="#{dur}" calcMode="#{mode}" repeatCount="indefinite"/>\n)
    end

    private def animate_transform(type : String, values : String, key_times : String, dur : String, mode : String) : String
      %(<animateTransform attributeName="transform" type="#{type}" values="#{values}" keyTimes="#{key_times}" dur="#{dur}" calcMode="#{mode}" repeatCount="indefinite"/>\n)
    end

    # Angles for linear interpolation: each step takes the short way round,
    # so a turn from 350 to 10 does not spin backwards through 180.
    def unwrap(angles : Array(Int32)) : Array(Int32)
      out_angles = [] of Int32
      running = 0
      angles.each_with_index do |a, k|
        if k == 0
          running = a
        else
          d = (a - angles[k - 1]) % 360 # floored: 0..359
          running += d > 180 ? d - 360 : d
        end
        out_angles << running
      end
      out_angles
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
            sx = (0.6 * Battle.lcos(r.scan) / 100000.0).round(3)
            sy = (0.6 * Battle.lsin(r.scan) / 100000.0).round(3)
            pik << "line from R#{i} to R#{i} + (#{sx}, #{sy}) thin dotted color #{color}\n"
            dx = (0.25 * Battle.lcos(r.heading) / 100000.0).round(3)
            dy = (0.25 * Battle.lsin(r.heading) / 100000.0).round(3)
            pik << "line from R#{i} to R#{i} + (#{dx}, #{dy}) thick color black\n"
            if r.fired
              cx = (0.2 * Battle.lcos(r.cannon) / 100000.0).round(3)
              cy = (0.2 * Battle.lsin(r.cannon) / 100000.0).round(3)
              pik << "line from R#{i} to R#{i} + (#{cx}, #{cy}) thick color red\n"
            end
          end
          label = r.active ? "#{r.name} #{r.damage}%" : "#{r.name} X"
          pik << "text \"#{pikchr_text(label)}\" small at R#{i}.n + (0, 0.12)\n"
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
    # The program is parsed exactly once, under the parser's budgets; on an
    # error the passes it managed are shown, never a second unbounded run.
    DERIVATION_LINES =  60 # passes shown: the first two thirds and the last third
    DERIVATION_WIDTH = 300 # glyphs per line before an ellipsis

    def derivation_section(src : String) : String
      String.build do |md|
        md << "## Derivation\n\n"
        program = Compiler::Program.new(src)
        error = nil
        begin
          Compiler::Parser.parse(program)
        rescue e : Compiler::Parser::Error
          error = e
        end
        md << "**Parse error:** #{inline(error.message.to_s)}\n\n" if error
        md << "#{program.passes} passes, #{program.size} nodes.\n\n" unless error
        md << fenced(bounded_derivation(program)) if program.passes > 0
        unless error
          problems = Compiler::Checker.check(program)
          if problems.empty?
            md << "\nChecks passed: every name is defined and every call has the right number of arguments.\n"
          else
            md << "\n**Problems:**\n\n"
            problems.each { |problem| md << "- #{inline(problem.to_s)}\n" }
          end
        end
      end
    end

    # The derivation with long runs of passes and long lines elided, so the
    # page stays readable and its size bounded whatever was submitted.
    def bounded_derivation(program : Compiler::Program) : String
      lines = program.derivation.lines
      if lines.size > DERIVATION_LINES
        head = DERIVATION_LINES * 2 // 3
        tail = DERIVATION_LINES - head
        lines = lines.first(head) + ["    ... #{lines.size - DERIVATION_LINES} passes elided ..."] + lines.last(tail)
      end
      lines.map { |line| line.size > DERIVATION_WIDTH ? line[0, DERIVATION_WIDTH] + " …(#{line.size - DERIVATION_WIDTH} more)" : line }.join('\n')
    end
  end
end
