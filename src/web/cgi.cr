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
require "../battle/svg_replay"
require "../tournament/tournament"
require "./docs"
require "./robot_api"

module CrystalRobots::Web
  # The example robots, embedded at compile time so the CGI needs no
  # filesystem access. The list is whatever `examples/*.cr` holds when the
  # binary is built, in name order.
  EXAMPLES = {% begin %}
    {
      {% for file in `ls #{__DIR__}/../../examples/*.cr`.split.sort %}
        {{ file.split("/").last.gsub(/\.cr$/, "") }} => {{ read_file(file) }},
      {% end %}
    }
  {% end %}

  # Robots saved as Fossil wiki pages. A page named `robot/<name>` holds
  # Markdown with exactly one fenced code block, which is the robot source.
  #
  # All pages are read in ONE `fossil sql --readonly` query over the wiki
  # tables (latest version of every `robot/*` page, as hex so the rows stay
  # one line each); names, descriptions and sources come from that single
  # read, nothing is cached across requests, and the repository is opened
  # read-only so no write, temporary or otherwise, leaves the workspace.
  class WikiRobots
    PREFIX = "robot/"
    FENCE  = /^(`{3,})[^\n]*\n(.*?)\n\1[ \t]*$/m
    # Names are what shows in headings, links and labels; keep them plain.
    NAME = /\A[A-Za-z0-9][A-Za-z0-9 _.-]{0,39}\z/

    QUERY = "SELECT substr(tag.tagname, 6) || ' ' || hex(content(b.uuid)) " \
            "FROM tagxref JOIN tag USING(tagid) JOIN blob b ON b.rid = tagxref.rid " \
            "WHERE tag.tagname GLOB 'wiki-robot/*' " \
            "AND tagxref.mtime = (SELECT max(mtime) FROM tagxref x WHERE x.tagid = tagxref.tagid)"

    # name (without prefix) => page text
    getter pages : Hash(String, String)
    getter names : Array(String)

    def initialize(@pages : Hash(String, String), @limit : Int32 = 20_000)
      @names = @pages.keys.select { |n| n =~ NAME }.sort
    end

    # For specs and other readers that already hold the pages.
    def self.from_pages(pages : Hash(String, String), limit : Int32 = 20_000) : WikiRobots
      new(pages.each_with_object({} of String => String) { |(page, text), h| h[page[PREFIX.size..]] = text if page.starts_with?(PREFIX) }, limit)
    end

    # The deployed repository, if Fossil told us where it is.
    def self.for_repository(repository : String?) : WikiRobots
      return new({} of String => String) unless repository && File.exists?(repository)
      new(parse_rows(fossil(["sql", "--readonly", "-R", repository, QUERY])))
    end

    # Each row is "<name> <hex>"; the name (a wiki page name after the
    # `robot/` prefix) may itself contain spaces, but the hex payload never
    # does, so the row splits at the LAST space, not the first.
    def self.parse_rows(output : String) : Hash(String, String)
      pages = {} of String => String
      output.each_line do |line|
        row = line.strip
        row = row[1..-2] if row.starts_with?('\'') && row.ends_with?('\'')
        name, _, hex = row.rpartition(' ')
        next if name.empty? || hex.empty?
        text = wiki_text(String.new(hex.hexbytes))
        pages[name[PREFIX.size..]] = text if text && name.starts_with?(PREFIX)
      end
      pages
    end

    # The page text inside a wiki artifact: the W card's payload. A deleted
    # page has an empty payload and is not a robot.
    def self.wiki_text(artifact : String) : String?
      m = artifact.match(/^W (\d+)\n/m)
      return nil unless m
      size = m[1].to_i
      return nil if size == 0
      start = m.end(0).not_nil!
      artifact.byte_slice(artifact.char_index_to_byte_index(start).not_nil!, size)
    end

    # The first paragraph of the page before its code block, for listings.
    def description(name : String) : String
      page = @pages[name]? || ""
      body = page.split(/^`{3,}/m, 2)[0]
      paragraph = body.split(/\n[ \t]*\n/).map(&.strip).find { |para| !para.empty? && !para.starts_with?("#") } || ""
      text = paragraph.gsub(/\s+/, " ")
      text.size > 160 ? text[0, 157] + "..." : text
    end

    # The source of the robot, or nil if the page has no single fence or the
    # fence is larger than a pasted robot may be.
    def source(name : String) : String?
      return nil unless @names.includes?(name)
      page = @pages[name]? || return nil
      fences = page.scan(FENCE)
      return nil unless fences.size == 1
      src = fences[0][2]
      src.size <= @limit ? src : nil
    end

    # Raised when `fossil sql` fails, so a broken read surfaces as a 500
    # through `CGI#serve` instead of silently rendering an empty listing.
    class QueryError < Exception
    end

    private def self.fossil(args : Array(String)) : String
      output = IO::Memory.new
      # Fossil serves an ext CGI extension a minimal environment (the CGI
      # variables only): no HOME, so `fossil sql` cannot locate its global
      # config database and refuses to run at all. Give it one; the value
      # doesn't matter for a --readonly query, only that it resolves.
      scrub = {"GATEWAY_INTERFACE" => nil, "PATH_INFO" => nil, "QUERY_STRING" => nil, "REQUEST_METHOD" => nil,
               "CONTENT_LENGTH" => nil, "SCRIPT_NAME" => nil, "HTTP_COOKIE" => nil,
               "HOME" => ENV["HOME"]? || ENV["FOSSIL_HOME"]? || "/tmp"}
      status = Process.run("fossil", args, env: scrub, output: output, error: Process::Redirect::Close)
      raise QueryError.new("fossil #{args.first}: exit #{status.exit_code}") unless status.success?
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

    # scheme://host, for building an absolute URL a visitor can copy and
    # paste anywhere (a tournament's share link), independent of whatever
    # page it happens to be shown on. Never built from the client-supplied
    # `Host:` header: that header is request data, not configuration, and a
    # crafted one would land unescaped in a share link everyone is handed.
    # `FOSSIL_URL` is the canonical base the server configures once for the
    # repository (Fossil's own fix for the same Host-header trust problem,
    # passed through to ext CGIs); with no such configuration, fall back to
    # `localhost` rather than guess from the request.
    def request_origin : String
      configured = env["FOSSIL_URL"]?
      return "http://localhost" if configured.nil? || configured.empty?
      uri = URI.parse(configured)
      host = uri.host
      return "http://localhost" unless host
      scheme = uri.scheme || "http"
      default_port = scheme == "https" ? 443 : 80
      port = uri.port && uri.port != default_port ? ":#{uri.port}" : ""
      "#{scheme}://#{host}#{port}"
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

    # Routes map to capability letters; the repository's grants decide who
    # holds them. Anonymous visitors are sent to log in; a logged-in user
    # without the letter is told which one is missing.
    def login_required : Nil
      if logged_in?
        reply("# Not allowed\n\nThis needs check-in permission (`i`) on the repository, which `#{inline(user)}` does not have. Return to the [overview](#{link_base}).\n", "403 Forbidden")
      else
        reply("# Log in first\n\nParsing and battles need a login with check-in permission. [Log in](#{login_link}) to continue, or return to the [overview](#{link_base}).\n", "403 Forbidden")
      end
    end

    # Battle spends CPU and parse is kept with it until the compiler runs
    # client-side; both need check-in (`i`), Setup and Admin included.
    def may_run? : Bool
      allowed?("i")
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
        reply("#{CrystalRobots.version_line}\n")
      when "docs"
        docs_redirect
      when /\Adocs\/(.*)\z/
        docs_file($1)
      when "parse"
        return login_required unless may_run?
        if method == "POST"
          source = HTTP::Params.parse(body)["source"]? || ""
          # A source this small round-trips through a GET like a pasted
          # battle robot does (`PASTE_LIMIT`, "travels in the battle page's
          # links"): redirecting there means the address bar, refresh and
          # back all land on a URL that reproduces this exact result.
          # A longer source cannot fit in a link, so it is rendered straight
          # from the POST body instead -- never lost, just not bookmarkable.
          if source.size <= PASTE_LIMIT
            redirect("#{form_base}/parse?src=#{URI.encode_www_form(source)}")
          else
            reply(parse_page(source))
          end
        else
          reply(parse_page(query["src"]? || ""))
        end
      when "battle"
        return login_required unless may_run?
        reply(battle_page)
      when "tournament"
        entrants = tournament_entrants(query)
        if entrants.empty?
          reply(tournament_form(query.fetch_all("pick")))
        else
          return login_required unless may_run?
          reply(tournament_ladder(query, entrants))
        end
      when /\Aexamples\/([a-z_]+)\z/
        name = $1
        if (src = EXAMPLES[name]?)
          reply(example_page(name, src))
        else
          not_found
        end
      when /\Awiki\/(.+)\z/
        return login_required unless may_run?
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

    # A redirect the browser follows right away: the address bar (and so
    # refresh and back) end up on the target URL, not the request that
    # produced it.
    def redirect(location : String) : Nil
      @out << "Status: 302 Found\r\nLocation: " << location << "\r\n\r\n"
    end

    def forbidden : Nil
      @out << "Status: 403 Forbidden\r\nContent-Type: text/html\r\n\r\n"
      @out << "<p>403 Forbidden. <a href=\"/login\">Log in</a> to access this resource.</p>"
    end

    def plain(status : String, text : String) : Nil
      @out << "Status: " << status << "\r\nContent-Type: text/plain\r\n\r\n" << text << "\n"
    end

    # The API reference. Built pages are served raw (they carry their own
    # styling and script); without a build the route explains how to make one.
    def docs_redirect : Nil
      if Docs.built?
        redirect("#{form_base}/docs/index.html")
      else
        reply("# API docs not built\n\nThis binary was built without `bin/crystal-robots build-docs`; run it and rebuild. [Back](#{link_base})\n", "404 Not Found")
      end
    end

    def docs_file(path : String) : Nil
      path = "index.html" if path.empty? || path.ends_with?('/')
      if (page = Docs.page(path))
        title, fragment = page
        # text/html whose outermost element is div.fossil-doc gets the skin
        @out << "Status: 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\r\n"
        @out << "<div class='fossil-doc' data-title='" << HTML.escape(title) << "'>\n" << fragment << "\n</div>\n"
      elsif (content = Docs.asset(path))
        @out << "Status: 200 OK\r\nContent-Type: " << Docs.mime(path) << "\r\n\r\n" << content
      else
        not_found
      end
    end

    def not_found : Nil
      reply("# Not found\n\nNo such page: #{inline(path)}. [Back](#{link_base})\n", "404 Not Found")
    end

    # User text inside Markdown prose or a table cell: HTML-escaped, with
    # the characters that would start markup or split a table neutralized.
    def inline(text : String) : String
      HTML.escape(text).gsub('|', "&#124;").gsub('`', "&#96;").gsub('*', "&#42;").gsub('_', "&#95;").gsub('[', "&#91;").gsub(']', "&#93;")
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
        md << "Version `#{CrystalRobots::VERSION}`, check-in `#{CrystalRobots.checkin_short}`"
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
        if may_run?
          md << "\n## Battle\n\n[Pick robots and fight](#{base}/battle) on the CROBOTS battlefield.\n"
          md << "\n## Parse your own\n\n"
          md << "<form method=\"post\" action=\"#{form_base}/parse\">\n"
          md << "<textarea name=\"source\" rows=\"12\" cols=\"70\">puts 2 + (1 + 2) // 2 * 4</textarea><br>\n"
          md << "<button type=\"submit\">Parse</button>\n"
          md << "</form>\n\n"
        elsif logged_in?
          md << "\n## Battle and parse\n\nRunning battles and parsing your own robots needs check-in permission (`i`) on this repository; ask the maintainer for it.\n\n"
        else
          md << "\n## Battle and parse\n\nRunning battles and parsing your own robots needs a login with check-in permission: [log in](#{login_link(form_base)}) and this page will offer both.\n\n"
        end
        md << "\n## Tournament\n\n[Pick robots and run a tournament](#{base}/tournament): every saved robot and example can enter, pools then a bracket, one champion.\n\n"
        md << "See [docs/PARSER.md](/doc/trunk/docs/PARSER.md) for how the passes work, "
        md << "[docs/PLAN.md](/doc/trunk/docs/PLAN.md) for what comes next"
        md << (Docs.built? ? ", and the [API reference](#{base}/docs/index.html) for the robot builtins and the compiler.\n" : ".\n")
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

    # The editor and the results on one page, always in this order: a
    # refresh or Back must show the same source above the same passes, so
    # the form is rendered here every time, never a results-only page.
    def parse_page(source : String) : String
      String.build do |md|
        md << "# Parse\n\n[Back](#{link_base})\n\n"
        md << "<form method=\"post\" action=\"#{form_base}/parse\">\n"
        md << "<textarea name=\"source\" rows=\"12\" cols=\"70\">" << HTML.escape(source) << "</textarea><br>\n"
        md << "<button type=\"submit\">Parse</button>\n"
        md << "</form>\n\n"
        md << RobotAPI.panel("#{link_base}/docs")
        if source.strip.empty?
          md << "Nothing to parse yet. Paste your robot above and press **Parse**.\n"
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
    # Shared with the browser-hosted `crd_battle_run` (`src/browser.cr`),
    # which draws with the same `Battle.svg_animation` this page's own
    # `svg_animation` delegates to below -- one renderer, not two.
    ROBOT_COLORS = Battle::ROBOT_COLORS
    ANIM_CPS     = Battle::ANIM_CPS
    ANIM_FRAMES  =    400 # keyframes recorded per match; SMIL interpolates between them
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
        md << RobotAPI.panel("#{link_base}/docs")
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

    # --- Tournament -------------------------------------------------------
    #
    # /tournament is a designer form (pick robots, an "everyone" link,
    # Start) over pools-then-bracket play (see ../tournament/tournament.cr).
    # A tournament is link-driven, GET-only and stateless like /battle: all
    # of its state — which robots, which stage, what has already been
    # decided — lives in the URL. Because playing a fight spends real
    # Battle::Field cycles, one request plays exactly one stage (the
    # pools, or one bracket round); the "run next round" link carries
    # everything already decided (serialized pools and rounds, plus the
    # seed to resume from) so earlier stages are never replayed.

    TOURNAMENT_CYCLE_LIMIT  = 30_000_i32 # a tournament is many fights, not one long replay; still enough for most pairs to decide
    TOURNAMENT_ENTRANTS_MAX =         32 # keeps pools, the bracket and the URL a sane size

    # Fossil's HTTP server reads a request line into a fixed-size buffer and
    # panics (dropping the connection) if a link is too long to fit; no
    # tournament link this app emits should ever get close, so anything
    # over this is refused in favor of a plain-word message instead of a
    # link Fossil might not be able to read back.
    TOURNAMENT_LINK_MAX_BYTES = 1800

    private def tournament_entrants(q : HTTP::Params) : Array(String)
      ex = q.fetch_all("r").select { |n| EXAMPLES.has_key?(n) }
      saved = wiki_visible? ? q.fetch_all("w").select { |n| wiki.names.includes?(n) } : [] of String
      order_entrants((ex + saved).first(TOURNAMENT_ENTRANTS_MAX), q["order"]?)
    end

    private def order_entrants(entrants : Array(String), order : String?) : Array(String)
      order == "alpha" ? entrants.sort : entrants
    end

    # `picked` are entrants to pre-check, from the "everyone" link.
    def tournament_form(picked : Array(String) = [] of String) : String
      String.build do |md|
        md << "# Tournament\n\n[Back](#{link_base})\n\n"
        md << "Pick at least 3 robots, then press **Start tournament**. Everyone in a pool fights everyone else once; "
        md << "the top finishers go into a bracket; the bracket winner is the champion.\n\n"
        all_examples = EXAMPLES.keys.to_a
        all_saved = wiki_visible? ? wiki.names : [] of String
        unless (all_examples + all_saved).empty?
          everyone = (all_examples + all_saved).map { |n| "pick=#{URI.encode_www_form(n)}" }.join("&")
          everyone_link = guarded_link("#{link_base}/tournament?#{everyone}")
          if everyone_link
            md << "[Check everyone](#{everyone_link}) if everyone is playing.\n\n"
          else
            md << "Too many robots for one link; pick them by hand.\n\n"
          end
        end
        md << "<form method=\"get\" action=\"#{form_base}/tournament\">\n"
        md << "<p>Built-in examples:</p>\n"
        all_examples.each { |name| md << big_checkbox("r", name, picked.includes?(name)) }
        if wiki_visible? && !all_saved.empty?
          md << "<p>Saved robots:</p>\n"
          all_saved.each { |name| md << big_checkbox("w", name, picked.includes?(name)) }
        end
        md << "<details><summary>More choices</summary>\n"
        md << "<label>Seed <input type=\"number\" name=\"seed\" value=\"1\" min=\"0\"></label><br>\n"
        md << "<label>Cycle limit <input type=\"number\" name=\"limit\" value=\"#{TOURNAMENT_CYCLE_LIMIT}\" min=\"#{MOTION_STEP}\" max=\"#{WEB_CYCLE_MAX}\"></label><br>\n"
        md << "<label>Entrant order <select name=\"order\"><option value=\"given\">as picked</option><option value=\"alpha\">alphabetical</option></select></label>\n"
        md << "</details>\n"
        button = "<button type=\"submit\"#{" disabled" unless may_run?} style=\"font-size:1.3em;padding:0.3em 1em;\">Start tournament</button>"
        md << "<p>#{button}</p>\n</form>\n\n"
        if !may_run? && logged_in?
          md << "Running a tournament needs check-in permission (`i`) on this repository; ask the maintainer for it.\n"
        elsif !may_run?
          md << "Running a tournament needs a login with check-in permission: [log in](#{login_link(form_base + "/tournament")}) and this page will offer Start.\n"
        end
      end
    end

    private def big_checkbox(param : String, name : String, checked : Bool) : String
      mark = checked ? " checked" : ""
      "<label style=\"font-size:1.25em;\"><input type=\"checkbox\" name=\"#{param}\" value=\"#{HTML.escape(name)}\" " \
      "style=\"width:1.4em;height:1.4em;vertical-align:middle;\"#{mark}> #{HTML.escape(name)}</label><br>\n"
    end

    # Drives one stage of the tournament from the URL. State is a single
    # compact `mv` (moves) string: one letter per fight attempt actually
    # played so far, in the exact order the engine played them (pools
    # first, then each bracket round) — 'a' the first-listed entrant won,
    # 'b' the second, 't' no winner. Everything else (which pairs fought,
    # who advanced, standings, seeds) is derivable from entrants + seed +
    # limit + those outcomes, by literally replaying the tournament engine
    # with a fake "fight" that pops the next letter instead of running a
    # battle — no Battle::Field cycles are spent on already-decided fights,
    # and nothing but outcomes is serialized into the URL, so even a large
    # tournament's link stays well under what Fossil's HTTP server can
    # read back. The very first request (no `mv` yet) plays the pools;
    # once the pools and every already-decided round have been replayed
    # for free, exactly one more bracket round is played live.
    def tournament_ladder(q : HTTP::Params, entrants : Array(String)) : String
      return plain_error("Pick at least 3 robots to start a tournament.") if entrants.size < 3
      if (bad = missing_source(entrants))
        return plain_error("#{inline(bad)} has no code block yet.")
      end
      seed = q["seed"]?.try(&.to_u64?) || 1_u64
      limit = (q["limit"]?.try(&.to_i32?) || TOURNAMENT_CYCLE_LIMIT).clamp(MOTION_STEP.to_i32, WEB_CYCLE_MAX.to_i32)
      order = q["order"]?
      sources = tournament_sources(entrants)

      moves = (q["mv"]? || "").chars
      if moves.empty?
        return pools_page(entrants, seed, limit, order, sources) if q["go"]?
        return tournament_link_page(entrants, seed, limit, order)
      end

      cursor = MoveCursor.new(moves)
      replay = replay_fight(cursor)
      pool_stage = Tournament.play_pools(entrants, seed, limit, replay)
      pools = pool_stage.pools
      slots, total_rounds = Tournament.bracket_plan(pool_stage.advancers)
      resume = pool_stage.resume_seed
      rounds = [] of Tournament::Round
      current = slots
      idx = 0
      while cursor.remaining? && current.size > 1
        stage = Tournament.play_bracket_round(current, resume, limit, replay, total_rounds, idx)
        rounds << stage.round
        resume = stage.resume_seed
        current = stage.next_slots
        idx += 1
      end
      return champion(entrants, limit, pools, rounds, sources) if current.size <= 1 && !rounds.empty?

      unless round_fits_budget?(current, limit)
        return plain_error("That's too many robots for one round at this cycle limit; lower the cycle limit or pick fewer robots.")
      end
      stage = Tournament.play_bracket_round(current, resume, limit, tournament_fight(sources), total_rounds, idx)
      new_moves = moves.join + moves_for_rounds([stage.round])
      rounds = rounds + [stage.round]
      if stage.final
        champion(entrants, limit, pools, rounds, sources)
      else
        round_page(entrants, seed, limit, order, pools, rounds, new_moves)
      end
    end

    # The last line of defense against a hand-edited or truncated `mv=`: a
    # tampered-but-internally-consistent outcome string replays to a
    # different, attacker-chosen champion with no further checking, because
    # `replay_fight` above trusts every letter it is handed. Before a
    # champion is shown, every BRACKET fight recorded in `rounds` is run for
    # real, from its own recorded seed, and checked against the outcome the
    # (possibly tampered) `mv=` claims; any mismatch refuses the champion.
    # Pools are trusted as recorded, not re-verified: round-robin play is
    # many more fights than the bracket for the same entrant count, and a
    # tampered pool can only change seeding going into the bracket, which
    # the bracket re-check still catches at the one outcome that matters —
    # who the link ultimately crowns.
    private def champion(entrants : Array(String), limit : Int32, pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round), sources : Hash(String, String)) : String
      bracket_outcomes_match?(rounds, limit, sources) ? champion_page(entrants, limit, pools, rounds) : tampered_page
    end

    private def bracket_outcomes_match?(rounds : Array(Tournament::Round), limit : Int32, sources : Hash(String, String)) : Bool
      fight = tournament_fight(sources)
      rounds.all? do |round|
        round.matches.all? do |match|
          match.games.all? { |game| fight.call(game.entrants, game.seed, limit) == game.winner }
        end
      end
    end

    private def tampered_page : String
      plain_error("This link was changed: its recorded outcomes don't match what replaying the bracket's own seeds actually produces, so no champion is shown.")
    end

    private def missing_source(entrants : Array(String)) : String?
      entrants.find { |n| !EXAMPLES.has_key?(n) && wiki.source(n).nil? }
    end

    private def tournament_sources(entrants : Array(String)) : Hash(String, String)
      sources = {} of String => String
      entrants.each { |n| sources[n] = EXAMPLES[n]? || wiki.source(n).not_nil! }
      sources
    end

    private def tournament_fight(sources : Hash(String, String)) : Tournament::FightFn
      ->(entries : Array(String), seed : UInt64, limit : Int32) {
        battle_entries = entries.map { |n| {n, sources[n]} }
        field = Battle::Field.new(battle_entries, seed: seed, limit: limit.to_i64, max_frames: 2)
        field.run
        field.winner.try(&.name)
      }
    end

    # A position within an already-decided `mv` moves string, handed to a
    # replay `FightFn` (see below). Running past the end of the string is
    # not an error: it happens if a hand-edited or truncated URL is shorter
    # than the tournament it claims to encode, and is treated as a run of
    # no-winner fights rather than crashing the page.
    private class MoveCursor
      def initialize(@moves : Array(Char))
        @pos = 0
      end

      def remaining? : Bool
        @pos < @moves.size
      end

      def next! : Char
        c = @pos < @moves.size ? @moves[@pos] : 't'
        @pos += 1
        c
      end
    end

    # Reconstructs already-decided fights for free: pops the next letter
    # instead of running a battle, so replaying every pool and round
    # already recorded in the URL costs no Battle::Field cycles at all.
    private def replay_fight(cursor : MoveCursor) : Tournament::FightFn
      ->(entries : Array(String), seed : UInt64, limit : Int32) {
        case cursor.next!
        when 'a' then entries[0]
        when 'b' then entries[1]
        else          nil
        end
      }
    end

    private def move_char(winner : String?, entries : Array(String)) : Char
      return 't' unless winner
      winner == entries[0] ? 'a' : 'b'
    end

    # The moves for every fight attempt across the given pools, in the
    # exact order the engine played them (round-robin, then any tie-break
    # refights already appended to each pool's fight log).
    private def moves_for_pools(pools : Array(Tournament::PoolResult)) : String
      pools.flat_map(&.fights).map { |f| move_char(f.winner, f.entrants) }.join
    end

    # The moves for every fight attempt across the given bracket rounds; a
    # bye match has no games and so contributes nothing.
    private def moves_for_rounds(rounds : Array(Tournament::Round)) : String
      rounds.flat_map(&.matches).flat_map(&.games).map { |g| move_char(g.winner, g.entrants) }.join
    end

    # A fast, plain-words check on the cycles one stage is about to spend
    # (its fights at one attempt each), so a roster too big for the chosen
    # cycle limit fails immediately instead of running long. A no-winner
    # fight is refought, so the real cost can run a little higher than
    # this in the rare case several fights need it; the check is a sanity
    # gate on the common case, not a hard runtime cap.
    private def pools_fit_budget?(entrants : Array(String), limit : Int32) : Bool
      pairs = Tournament.pool_sizes(entrants.size).sum { |n| n * (n - 1) // 2 }
      pairs.to_i64 * limit <= SERIES_CYCLE_MAX
    end

    private def round_fits_budget?(slots : Array(String?), limit : Int32) : Bool
      non_bye = slots.each_slice(2).count { |pair| !pair[0].nil? && !pair[1].nil? }
      non_bye.to_i64 * 3 * limit <= SERIES_CYCLE_MAX
    end

    private def plain_error(message : String) : String
      "# Tournament\n\n[Back](#{link_base}/tournament)\n\n#{message}\n"
    end

    # Shown the instant the designer form is submitted, before any fight
    # runs: the tournament's link is the whole point of a link-driven page,
    # so a visitor gets it (to bookmark or share) without having to wait
    # for the pools to play. Revisiting this same link (without `go=1`)
    # always lands back here, not mid-tournament, so it is safe to share.
    # A link over `TOURNAMENT_LINK_MAX_BYTES` risks the request line Fossil's
    # HTTP server cannot read back (see the guard comment on the constant);
    # nil tells the caller to fall back to a plain-word message instead.
    private def guarded_link(url : String) : String?
      url.bytesize <= TOURNAMENT_LINK_MAX_BYTES ? url : nil
    end

    private def tournament_link_page(entrants : Array(String), seed : UInt64, limit : Int32, order : String?) : String
      config = tournament_config_parts(entrants, seed, limit, order).join("&")
      # The share text is a full absolute URL (copy-paste anywhere); the
      # Markdown link's target stays root-relative under `/ext/` so Fossil's
      # own prefixing lands it in the right place, while the Start button is
      # raw HTML, which Fossil does not rewrite, so it needs the full path.
      # Every piece is either trusted configuration (`request_origin`,
      # `form_base`) or percent-encoded (`config`), so it is safe to splice
      # straight into Markdown link text and a raw `href` with no further
      # escaping — it cannot contain a `]`, a backtick or a quote.
      share_url = "#{request_origin}#{form_base}/tournament?#{config}"
      unless guarded_link(share_url)
        return plain_error("That's too many robots for one tournament link; pick fewer robots.")
      end
      link_target = "#{link_base}/tournament?#{config}"
      start_href = "#{form_base}/tournament?#{config}&go=1"
      String.build do |md|
        md << "# Tournament\n\n[Back](#{link_base})\n\n"
        md << "Your tournament is ready with #{entrants.size} robots. Save or share this link to come back to it any time:\n\n"
        md << "`#{share_url}`\n\n"
        md << "[#{share_url}](#{link_target})\n\n"
        md << "<p><a href=\"#{start_href}\"><button style=\"font-size:1.3em;padding:0.3em 1em;\">Start round 1</button></a></p>\n"
      end
    end

    private def pools_page(entrants : Array(String), seed : UInt64, limit : Int32, order : String?, sources : Hash(String, String)) : String
      unless pools_fit_budget?(entrants, limit)
        return plain_error("That's too many robots for one round at this cycle limit; lower the cycle limit or pick fewer robots.")
      end
      stage = Tournament.play_pools(entrants, seed, limit, tournament_fight(sources))
      moves = moves_for_pools(stage.pools)
      next_link = "#{link_base}/tournament?#{tournament_config_parts(entrants, seed, limit, order).join("&")}&mv=#{URI.encode_www_form(moves)}"
      render_ladder_page("The pools are done.", entrants, limit, stage.pools, [] of Tournament::Round, guarded_link(next_link))
    end

    private def round_page(entrants : Array(String), seed : UInt64, limit : Int32, order : String?, pools : Array(Tournament::PoolResult),
                           rounds : Array(Tournament::Round), moves : String) : String
      next_link = "#{link_base}/tournament?#{tournament_config_parts(entrants, seed, limit, order).join("&")}&mv=#{URI.encode_www_form(moves)}"
      render_ladder_page("The #{rounds.last.label.downcase} is done.", entrants, limit, pools, rounds, guarded_link(next_link))
    end

    private def render_ladder_page(status : String, entrants : Array(String), limit : Int32, pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round), next_link : String?) : String
      String.build do |md|
        md << "# Tournament\n\n[Back](#{link_base})\n\n"
        if next_link
          md << "#{status} [Run next round →](#{next_link})\n\n"
        else
          md << "#{status} This tournament's link would be too long to continue from here; try fewer robots or a smaller cycle limit next time.\n\n"
        end
        md << "```pikchr\n" << pikchr_ladder(pools, rounds, nil) << "```\n\n"
        pools.each_with_index { |p, i| md << render_pool(p, i, limit) }
        rounds.each { |r| md << render_round(r, limit) }
        md << "[Run next round →](#{next_link})\n" if next_link
      end
    end

    private def champion_page(entrants : Array(String), limit : Int32, pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round)) : String
      champion = rounds.last.matches.first.winner
      String.build do |md|
        md << "# 🏆 #{inline(champion)} wins the Tournament! 🏆\n\n[Back](#{link_base})\n\n"
        md << "```pikchr\n" << pikchr_trophy(champion) << "```\n\n"
        md << "```pikchr\n" << pikchr_ladder(pools, rounds, champion) << "```\n\n"
        pools.each_with_index { |p, i| md << render_pool(p, i, limit) }
        rounds.each { |r| md << render_round(r, limit) }
      end
    end

    # A fight's replay is a `/battle` link for its two entrants at its own
    # seed; the cycle limit only changes how the replay is paced, not
    # which fight it is, so any value round-trips the correct match.
    private def fight_replay_link(a : String, b : String, seed : UInt64, limit : Int32) : String
      params = [a, b].map { |n| EXAMPLES.has_key?(n) ? "r=#{n}" : "w=#{URI.encode_www_form(n)}" }
      "#{link_base}/battle?#{params.join("&")}&seed=#{seed}&limit=#{limit}"
    end

    private def render_pool(pool : Tournament::PoolResult, index : Int32, limit : Int32) : String
      String.build do |md|
        md << "### Pool #{('A'.ord + index).chr}: #{pool.entrants.map { |n| inline(n) }.join(", ")}\n\n"
        md << "| Robot | Points | Rank |\n| --- | --- | --- |\n"
        pool.standings.each { |s| md << "| #{inline(s.name)} | #{s.points} | #{s.rank} |\n" }
        md << "\n| Fight | Winner | |\n| --- | --- | --- |\n"
        pool.fights.each do |f|
          winner = f.winner ? inline(f.winner.not_nil!) : "no winner, refought"
          link = fight_replay_link(f.entrants[0], f.entrants[1], f.seed, limit)
          md << "| #{inline(f.entrants[0])} vs #{inline(f.entrants[1])} (seed #{f.seed}) | #{winner} | [replay](#{link}) |\n"
        end
        md << "\n"
      end
    end

    private def render_round(round : Tournament::Round, limit : Int32) : String
      String.build do |md|
        md << "### #{round.label}\n\n"
        round.matches.each do |m|
          a, b = m.entrants[0], m.entrants[1]
          if a.nil? || b.nil?
            md << "- **#{inline(m.winner)}** advances on a bye\n"
          else
            games = m.games.map_with_index { |g, i| "[game #{i + 1}](#{fight_replay_link(a, b, g.seed, limit)})" }.join(", ")
            md << "- #{inline(a)} vs #{inline(b)}: **#{inline(m.winner)}** wins (#{games})\n"
          end
        end
        md << "\n"
      end
    end

    private def pik_str(text : String) : String
      %("#{pikchr_text(text)}")
    end

    private def pikchr_trophy(champion : String) : String
      String.build do |pik|
        pik << "CUP: ellipse wid 1.1in ht 0.6in fill 0xFFD700 color 0xB8860B\n"
        pik << "STEM: box wid 0.16in ht 0.35in fill 0xFFD700 color 0xB8860B with .n at CUP.s\n"
        pik << "box wid 0.7in ht 0.12in fill 0xFFD700 color 0xB8860B with .n at STEM.s\n"
        pik << "text #{pik_str(champion)} big bold at CUP.n + (0,0.35in)\n"
      end
    end

    # A schematic ladder: pools left to right in one row, each completed
    # bracket round in its own row below, the champion (once known) at
    # the bottom. Rows are spaced at a fixed gap rather than hugging their
    # content, so a variable number of matches per round never overlaps
    # the row below it.
    private def pikchr_ladder(pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round), champion : String?) : String
      String.build do |pik|
        pik << "boxwid = 1.3in; boxht = 0.35in\n"
        pools.each_with_index do |pool, i|
          name = "PL#{i}"
          top = pool.standings.first?
          if i == 0
            pik << "#{name}: box #{pik_str("Pool #{('A'.ord + i).chr}")} bold fill 0xADD8E6\n"
          else
            pik << "#{name}: box #{pik_str("Pool #{('A'.ord + i).chr}")} bold fill 0xADD8E6 with .w at PL#{i - 1}.e + (0.3in,0)\n"
          end
          pik << "text #{pik_str(top ? "#{top.name} #{top.points}pt" : "-")} small with .n at #{name}.s\n"
        end
        rounds.each_with_index do |round, ri|
          gap = (ri + 1) * 1.0
          round.matches.each_with_index do |m, mi|
            name = "RD#{ri}_#{mi}"
            versus = "#{m.entrants[0] || "bye"} v #{m.entrants[1] || "bye"}"
            if mi == 0
              pik << "#{name}: box #{pik_str(round.label)} bold fill 0xFFFFCC with .n at PL0.s - (0,#{gap}in)\n"
            else
              pik << "#{name}: box #{pik_str(round.label)} bold fill 0xFFFFCC with .w at RD#{ri}_#{mi - 1}.e + (0.3in,0)\n"
            end
            pik << "text #{pik_str(versus)} small with .n at #{name}.s\n"
            pik << "text #{pik_str("winner: #{m.winner}")} small with .n at last.s\n"
          end
        end
        if champion
          gap = (rounds.size + 1) * 1.0
          pik << "CH: box #{pik_str("Champion")} bold fill 0xFFD700 with .n at PL0.s - (0,#{gap}in)\n"
          pik << "text #{pik_str(champion)} bold with .n at CH.s\n"
        end
        # Arrows: each fight's winner flows down into the next round's slot
        # (match `mi` of round `ri` feeds match `mi // 2` of round `ri + 1`,
        # the same pairing `Tournament.play_bracket` used to build it), and
        # the final's winner flows into the champion box, so the bracket
        # reads as a flow, not a grid of unconnected boxes.
        rounds.each_with_index do |round, ri|
          if (next_round = rounds[ri + 1]?)
            round.matches.each_index { |mi| pik << "arrow from RD#{ri}_#{mi}.s to RD#{ri + 1}_#{mi // 2}.n\n" }
          elsif champion
            pik << "arrow from RD#{ri}_0.s to CH.n\n"
          end
        end
      end
    end

    # --- URL state for the ladder pages ------------------------------

    # The tournament's configuration (which robots, seed, limit, order) as
    # query parts: the part of the URL that stays fixed across every stage,
    # shared by the pre-fight link page and every ladder page's own link.
    private def tournament_config_parts(entrants : Array(String), seed : UInt64, limit : Int32, order : String?) : Array(String)
      parts = [] of String
      entrants.each { |n| parts << (EXAMPLES.has_key?(n) ? "r=#{URI.encode_www_form(n)}" : "w=#{URI.encode_www_form(n)}") }
      parts << "seed=#{seed}"
      parts << "limit=#{limit}"
      parts << "order=#{URI.encode_www_form(order)}" if order
      parts
    end

    # The whole match as one SVG with native (SMIL) animation: no script,
    # so it works under Fossil's content security policy. `Battle.svg_animation`
    # (`src/battle/svg_replay.cr`) is the real implementation, shared with
    # the browser build's `crd_battle_run` (`src/browser.cr`) so there is
    # exactly one renderer for the same `Battle::Field` wherever it ran.
    def svg_animation(field : Battle::Field, cps : Int32 = ANIM_CPS) : String
      Battle.svg_animation(field, cps)
    end

    # Angles for linear interpolation: each step takes the short way round,
    # so a turn from 350 to 10 does not spin backwards through 180. See
    # `Battle.unwrap` (`src/battle/svg_replay.cr`).
    def unwrap(angles : Array(Int32)) : Array(Int32)
      Battle.unwrap(angles)
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
