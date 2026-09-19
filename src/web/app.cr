require "./capabilities"
require "./request"
require "./response"
require "./markdown"
require "./pikchr"
require "./wiki_robots"
require "../compiler/parser"
require "../compiler/checker"
require "../battle/field"
require "../battle/match"
require "../tournament/tournament"

# The router: one method per route, each returning a `Response` Fossil
# wraps in Markdown chrome.
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
    elsif (name = path.lchop?("/wiki/"))
      wiki_robot(req, name)
    elsif path == "/tournament"
      tournament_page(req)
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

      if Capabilities.can_read_wiki?(req.capabilities)
        saved = WikiRobots.names
        unless saved.empty?
          io << "\n## Saved robots\n\n"
          saved.each { |name| io << "- [" << name << "](" << req.link("/wiki/#{name}") << ")\n" }
        end
      end
    end
    Response.new(md)
  end

  private def self.wiki_robot(req : Request, name : String) : Response
    unless Capabilities.can_read_wiki?(req.capabilities)
      return Response.new("# crystal-robots\n\nLog in to see saved robots.\n", status: 403)
    end
    source = EXAMPLE_NAME.matches?(name) ? WikiRobots.source(name) : nil
    unless source
      return Response.new("# Not found\n\nNo saved robot named #{Markdown.escape(name)}.\n", status: 404)
    end

    md = String.build do |io|
      io << "# " << name << " (saved robot)\n\n"
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

  # GET shows a checkbox per example robot, one per saved (wiki) robot
  # if the visitor can read wiki pages, and a seed field; POST runs one
  # seeded match among the checked robots (two to four) up to
  # WEB_CYCLE_LIMIT and shows the outcome as a table plus a Pikchr frame
  # of the final field. Needs run capability (i), the same as parsing.
  private def self.battle_page(req : Request) : Response
    unless Capabilities.can_run?(req.capabilities)
      return Response.new("# Battle\n\nLog in to run a battle.\n", status: 403)
    end

    examples = example_names
    saved = Capabilities.can_read_wiki?(req.capabilities) ? WikiRobots.names : [] of String
    seed_text = req.params["seed"]? || ""

    md = String.build do |io|
      io << "# Battle\n\n"
      io << "[back to the overview](" << req.link("/") << ")\n\n"
      io << %(<form method="post" action="#{req.link("/battle")}">\n)
      io << "Examples:<br>\n"
      examples.each do |n|
        checked = req.params.has_key?("pick_#{n}") ? " checked" : ""
        io << %(<label><input type="checkbox" name="pick_#{n}"#{checked}> #{n}</label><br>\n)
      end
      unless saved.empty?
        io << "Saved robots:<br>\n"
        saved.each do |n|
          checked = req.params.has_key?("pick_wiki_#{n}") ? " checked" : ""
          io << %(<label><input type="checkbox" name="pick_wiki_#{n}"#{checked}> #{n}</label><br>\n)
        end
      end
      io << %(Seed (optional): <input type="text" name="seed" value="#{html_escape(seed_text)}"><br>\n)
      io << %(<input type="submit" value="Fight">\n)
      io << "</form>\n"

      if req.method == "POST"
        io << "\n## Result\n\n"
        run_battle(io, picked_robots(req, examples, saved), seed_text)
      end
    end
    Response.new(md)
  end

  # `wiki` distinguishes a saved robot from an example so a page built
  # from a `PickedRobot` (a tournament's link, a fight's replay link)
  # can pick the right query parameter (`pick_NAME` vs `pick_wiki_NAME`)
  # to name it again.
  private record PickedRobot, name : String, source : String, wiki : Bool = false

  private def self.picked_robots(req : Request, examples : Array(String), saved : Array(String)) : Array(PickedRobot)
    picked = [] of PickedRobot
    examples.each do |n|
      picked << PickedRobot.new(n, File.read("examples/#{n}.cr")) if req.params.has_key?("pick_#{n}")
    end
    saved.each do |n|
      next unless req.params.has_key?("pick_wiki_#{n}")
      source = WikiRobots.source(n)
      picked << PickedRobot.new(n, source, wiki: true) if source
    end
    picked
  end

  private def self.run_battle(io : IO, picked : Array(PickedRobot), seed_text : String) : Nil
    if picked.size < 2 || picked.size > 4
      io << "Pick two to four robots.\n"
      return
    end
    seed = seed_text.empty? ? nil : seed_text.to_i?
    if !seed_text.empty? && seed.nil?
      io << "Seed must be a whole number.\n"
      return
    end

    begin
      programs = picked.map { |p| Compiler::Parser.new(p.source).program }
    rescue e : Compiler::Parser::Error
      io << "Could not run: " << Markdown.escape(e.message || "a robot did not parse") << "\n"
      return
    end

    field = Battle::Field.new(picked.map(&.name), seed)
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

  # --- Tournament -------------------------------------------------------
  #
  # /tournament is a designer form (pick robots, a "Check everyone" link,
  # Start) over pools-then-bracket play (see ../tournament/tournament.cr).
  # Like /battle it is link-driven and stateless: everything already
  # decided lives in the URL as a compact `mv` (moves) string, one letter
  # per fight attempt actually played so far, in the exact order the
  # engine played them (pools first, then each bracket round) -- 'a' the
  # first-listed entrant won, 'b' the second, 't' no winner. Replaying an
  # already-decided fight from its letter costs no Battle::Field cycles
  # at all, so one HTTP request only ever pays for the pools or exactly
  # one new bracket round, never fights already settled by an earlier
  # request.

  # Matches WEB_CYCLE_LIMIT: real CROBOTS-style robots often take tens
  # of thousands of rounds to decide a fight (a plain /battle between
  # two examples measured 39540 rounds to a winner), so a tournament's
  # per-fight limit needs the same headroom, not a smaller one, or
  # every fight in every pool times out into "no winner" and the whole
  # tournament degrades into tie-break cascades that never really fight.
  TOURNAMENT_CYCLE_LIMIT  = WEB_CYCLE_LIMIT
  TOURNAMENT_MIN_ENTRANTS = 3

  # A rough sanity gate (not a hard runtime cap: a no-winner fight is
  # refought, so the real cost can run a little higher) on the cycles
  # one stage is about to spend, so a big "Check everyone" roster at a
  # generous cycle limit fails fast with a plain message instead of
  # tying up one HTTP request for minutes.
  SERIES_CYCLE_MAX = 2_000_000_i64

  private def self.pools_fit_budget?(entrants : Array(String), limit : Int32) : Bool
    pairs = Tournament.pool_sizes(entrants.size).sum { |n| n * (n - 1) // 2 }
    pairs.to_i64 * limit <= SERIES_CYCLE_MAX
  end

  private def self.round_fits_budget?(slots : Array(String?), limit : Int32) : Bool
    non_bye = slots.each_slice(2).count { |pair| !pair[0].nil? && !pair[1].nil? }
    non_bye.to_i64 * 3 * limit <= SERIES_CYCLE_MAX
  end

  private def self.tournament_page(req : Request) : Response
    unless Capabilities.can_run?(req.capabilities)
      return Response.new("# Tournament\n\nLog in to run a tournament.\n", status: 403)
    end
    examples = example_names
    saved = Capabilities.can_read_wiki?(req.capabilities) ? WikiRobots.names : [] of String
    picked = picked_robots(req, examples, saved)
    picked.empty? ? tournament_form(req, examples, saved) : tournament_ladder(req, picked)
  end

  private def self.tournament_form(req : Request, examples : Array(String), saved : Array(String)) : Response
    md = String.build do |io|
      io << "# Tournament\n\n[back to the overview](" << req.link("/") << ")\n\n"
      io << "Pick at least 3 robots, then press **Start tournament**. Everyone in a pool fights "
      io << "everyone else once; the top finishers go into a bracket; the bracket winner is the champion.\n\n"
      unless (examples + saved).empty?
        everyone = (examples.map { |n| "pick_#{n}=on" } + saved.map { |n| "pick_wiki_#{n}=on" }).join("&")
        io << "[Check everyone](" << req.link("/tournament?#{everyone}") << ") if everyone is playing.\n\n"
      end
      io << %(<form method="get" action="#{req.link("/tournament")}">\n)
      io << "Examples:<br>\n"
      examples.each { |n| io << %(<label><input type="checkbox" name="pick_#{n}"> #{n}</label><br>\n) }
      unless saved.empty?
        io << "Saved robots:<br>\n"
        saved.each { |n| io << %(<label><input type="checkbox" name="pick_wiki_#{n}"> #{n}</label><br>\n) }
      end
      io << %(Seed (optional): <input type="text" name="seed"><br>\n)
      io << %(<input type="submit" value="Start tournament">\n)
      io << "</form>\n"
    end
    Response.new(md)
  end

  # Drives one stage of the tournament from the URL: the very first
  # request (no `mv` yet, no `go`) shows the shareable link page; adding
  # `go=on` plays the pools; from then on, each `mv`-carrying link
  # replays every already-decided fight for free and plays exactly one
  # more bracket round live.
  private def self.tournament_ladder(req : Request, picked : Array(PickedRobot)) : Response
    if picked.size < TOURNAMENT_MIN_ENTRANTS
      return tournament_error(req, "Pick at least 3 robots to start a tournament.")
    end

    begin
      picked.each { |p| Compiler::Parser.new(p.source).program }
    rescue e : Compiler::Parser::Error
      return tournament_error(req, "Could not run: #{Markdown.escape(e.message || "a robot did not parse")}")
    end

    seed = req.params["seed"]?.try(&.to_i?) || 1
    limit = (req.params["limit"]?.try(&.to_i?) || TOURNAMENT_CYCLE_LIMIT).clamp(100, WEB_CYCLE_LIMIT)
    names = picked.map(&.name)
    sources = names.zip(picked.map(&.source)).to_h

    moves = (req.params["mv"]? || "").chars
    if moves.empty?
      return pools_page(req, picked, seed, limit, sources) if req.params.has_key?("go")
      return tournament_link_page(req, picked, seed, limit)
    end

    cursor = MoveCursor.new(moves)
    replay = replay_fight(cursor)
    pools = Tournament.play_pools(names, seed, limit, replay)
    slots, total_rounds = Tournament.bracket_plan(Tournament.advancers(pools))
    resume = seed + pools.sum(&.fights.size)
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
    return champion(req, picked, limit, pools, rounds, sources) if current.size <= 1 && !rounds.empty?

    unless round_fits_budget?(current, limit)
      return tournament_error(req, "That's too many robots for one round at this cycle limit; lower the cycle limit or pick fewer robots.")
    end
    stage = Tournament.play_bracket_round(current, resume, limit, tournament_fight(sources), total_rounds, idx)
    new_moves = moves.join + moves_for_rounds([stage.round])
    rounds = rounds + [stage.round]
    if stage.final
      champion(req, picked, limit, pools, rounds, sources)
    else
      round_page(req, picked, seed, limit, pools, rounds, new_moves)
    end
  end

  # The last line of defense against a hand-edited or truncated `mv=`:
  # a tampered-but-internally-consistent moves string would otherwise
  # replay to a different, attacker-chosen champion with no further
  # checking, since `replay_fight` above trusts every letter it is
  # handed. Before a champion is shown, every bracket fight recorded in
  # `rounds` is run for real, from its own recorded seed, and checked
  # against the outcome `mv=` claims; any mismatch refuses the
  # champion instead of crowning one. Pools are trusted as recorded,
  # not re-verified: round-robin play is many more fights than the
  # bracket for the same entrant count, and a tampered pool can only
  # change seeding going into the bracket, which this re-check still
  # catches at the one outcome that matters -- who the link ultimately
  # crowns.
  private def self.champion(req : Request, picked : Array(PickedRobot), limit : Int32, pools : Array(Tournament::PoolResult),
                            rounds : Array(Tournament::Round), sources : Hash(String, String)) : Response
    bracket_outcomes_match?(rounds, limit, sources) ? champion_page(req, picked, limit, pools, rounds) : tampered_page(req)
  end

  private def self.bracket_outcomes_match?(rounds : Array(Tournament::Round), limit : Int32, sources : Hash(String, String)) : Bool
    fight = tournament_fight(sources)
    rounds.all? do |round|
      round.matches.all? do |match|
        match.games.all? { |game| fight.call(game.entrants, game.seed, limit) == game.winner }
      end
    end
  end

  private def self.tampered_page(req : Request) : Response
    tournament_error(req, "This link was changed: its recorded outcomes don't match what replaying the bracket's own seeds actually produces, so no champion is shown.")
  end

  # A real fight: parses each entrant's source fresh (they are tiny, and
  # a tournament's whole point is running many of them), plays it out on
  # a real Battle::Field, and reports the sole survivor, or nil for no
  # winner (a draw, or the cycle limit reached with more than one robot
  # still alive).
  private def self.tournament_fight(sources : Hash(String, String)) : Tournament::FightFn
    ->(entries : Array(String), seed : Int32, limit : Int32) {
      programs = entries.map { |n| Compiler::Parser.new(sources[n]).program }
      field = Battle::Field.new(entries, seed)
      match = Battle::Match.new(field, programs, cycle_limit: limit)
      match.run
      survivors = field.robots.select(&.alive?)
      survivors.size == 1 ? survivors[0].name : nil
    }
  end

  # A position within an already-decided `mv` moves string. Running past
  # the end is not an error: a hand-edited or truncated link shorter
  # than the tournament it claims to encode is treated as a run of
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
  # instead of running a battle.
  private def self.replay_fight(cursor : MoveCursor) : Tournament::FightFn
    ->(entries : Array(String), seed : Int32, limit : Int32) {
      case cursor.next!
      when 'a' then entries[0]
      when 'b' then entries[1]
      else          nil
      end
    }
  end

  private def self.move_char(winner : String?, entries : Array(String)) : Char
    return 't' unless winner
    winner == entries[0] ? 'a' : 'b'
  end

  private def self.moves_for_pools(pools : Array(Tournament::PoolResult)) : String
    pools.flat_map(&.fights).map { |f| move_char(f.winner, f.entrants) }.join
  end

  # A bye match has no games, so it contributes nothing to the moves.
  private def self.moves_for_rounds(rounds : Array(Tournament::Round)) : String
    rounds.flat_map(&.matches).flat_map(&.games).map { |g| move_char(g.winner, g.entrants) }.join
  end

  private def self.tournament_error(req : Request, message : String) : Response
    Response.new("# Tournament\n\n[back to the overview](#{req.link("/")})\n\n#{message}\n")
  end

  # The tournament's configuration (which robots, seed, limit) as a
  # query string: the part of the URL that stays fixed across every
  # stage, reusing the same `pick_NAME` / `pick_wiki_NAME` convention
  # the designer form and /battle already use, so a fight's replay link
  # and the tournament's own link are built the same way.
  private def self.tournament_config_query(picked : Array(PickedRobot), seed : Int32, limit : Int32) : String
    parts = picked.map { |p| p.wiki ? "pick_wiki_#{p.name}=on" : "pick_#{p.name}=on" }
    parts << "seed=#{seed}"
    parts << "limit=#{limit}"
    parts.join("&")
  end

  # Shown the instant the designer form is submitted, before any fight
  # runs: the tournament's link is the whole point of a link-driven
  # page, so a visitor gets it to bookmark or share without waiting for
  # the pools to play. Revisiting this same link (without `go`) always
  # lands back here, not mid-tournament, so it is safe to share.
  private def self.tournament_link_page(req : Request, picked : Array(PickedRobot), seed : Int32, limit : Int32) : Response
    config = tournament_config_query(picked, seed, limit)
    link_target = req.link("/tournament?#{config}")
    start_href = req.link("/tournament?#{config}&go=on")
    md = String.build do |io|
      io << "# Tournament\n\n[back to the overview](" << req.link("/") << ")\n\n"
      io << "Your tournament is ready with #{picked.size} robots. Save or share this link to come back to it any time:\n\n"
      io << "[" << link_target << "](" << link_target << ")\n\n"
      io << %(<p><a href="#{start_href}"><button style="font-size:1.3em;padding:0.3em 1em;">Start round 1</button></a></p>\n)
    end
    Response.new(md)
  end

  private def self.pools_page(req : Request, picked : Array(PickedRobot), seed : Int32, limit : Int32, sources : Hash(String, String)) : Response
    unless pools_fit_budget?(picked.map(&.name), limit)
      return tournament_error(req, "That's too many robots for one round at this cycle limit; lower the cycle limit or pick fewer robots.")
    end
    pools = Tournament.play_pools(picked.map(&.name), seed, limit, tournament_fight(sources))
    moves = moves_for_pools(pools)
    next_link = req.link("/tournament?#{tournament_config_query(picked, seed, limit)}&mv=#{moves}")
    render_ladder_page(req, "The pools are done.", picked, limit, pools, [] of Tournament::Round, next_link)
  end

  private def self.round_page(req : Request, picked : Array(PickedRobot), seed : Int32, limit : Int32,
                              pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round), moves : String) : Response
    next_link = req.link("/tournament?#{tournament_config_query(picked, seed, limit)}&mv=#{moves}")
    render_ladder_page(req, "The #{rounds.last.label.downcase} is done.", picked, limit, pools, rounds, next_link)
  end

  private def self.render_ladder_page(req : Request, status : String, picked : Array(PickedRobot), limit : Int32,
                                      pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round), next_link : String) : Response
    md = String.build do |io|
      io << "# Tournament\n\n[back to the overview](" << req.link("/") << ")\n\n"
      io << status << " [Run next round →](" << next_link << ")\n\n"
      io << Markdown.fence(Pikchr.ladder(pools, rounds, nil), "pikchr")
      pools.each_with_index { |p, i| io << render_pool(req, p, i, picked) }
      rounds.each { |r| io << render_round(req, r, picked) }
      io << "\n[Run next round →](" << next_link << ")\n"
    end
    Response.new(md)
  end

  private def self.champion_page(req : Request, picked : Array(PickedRobot), limit : Int32,
                                 pools : Array(Tournament::PoolResult), rounds : Array(Tournament::Round)) : Response
    champion = rounds.last.matches.first.winner
    md = String.build do |io|
      io << "# 🏆 " << champion << " wins the Tournament! 🏆\n\n[back to the overview](" << req.link("/") << ")\n\n"
      io << Markdown.fence(Pikchr.trophy(champion), "pikchr")
      io << Markdown.fence(Pikchr.ladder(pools, rounds, champion), "pikchr")
      pools.each_with_index { |p, i| io << render_pool(req, p, i, picked) }
      rounds.each { |r| io << render_round(req, r, picked) }
    end
    Response.new(md)
  end

  private def self.render_pool(req : Request, pool : Tournament::PoolResult, index : Int32, picked : Array(PickedRobot)) : String
    String.build do |io|
      io << "### Pool #{('A'.ord + index).chr}: #{pool.entrants.join(", ")}\n\n"
      io << "| Robot | Points | Rank |\n|---|---|---|\n"
      pool.standings.each { |s| io << "| #{s.name} | #{s.points} | #{s.rank} |\n" }
      io << "\n| Fight | Winner | |\n|---|---|---|\n"
      pool.fights.each do |f|
        winner = f.winner || "no winner, refought"
        link = fight_replay_link(req, f.entrants[0], f.entrants[1], f.seed, picked)
        io << "| #{f.entrants[0]} vs #{f.entrants[1]} (seed #{f.seed}) | #{winner} | [replay](#{link}) |\n"
      end
      io << "\n"
    end
  end

  private def self.render_round(req : Request, round : Tournament::Round, picked : Array(PickedRobot)) : String
    String.build do |io|
      io << "### #{round.label}\n\n"
      round.matches.each do |m|
        a, b = m.entrants[0], m.entrants[1]
        if a.nil? || b.nil?
          io << "- **#{m.winner}** advances on a bye\n"
        else
          games = m.games.map_with_index { |g, i| "[game #{i + 1}](#{fight_replay_link(req, a, b, g.seed, picked)})" }.join(", ")
          io << "- #{a} vs #{b}: **#{m.winner}** wins (#{games})\n"
        end
      end
      io << "\n"
    end
  end

  # A fight's replay pre-fills /battle's form with its two entrants and
  # seed already checked; unlike the tournament's own link, /battle is a
  # POST-only form (its result depends on running a real match, which
  # this app only ever does in response to a submitted form), so a
  # replay is one click of Fight away rather than an instant page.
  private def self.fight_replay_link(req : Request, a : String, b : String, seed : Int32, picked : Array(PickedRobot)) : String
    param = ->(name : String) {
      wiki = picked.find { |p| p.name == name }.try(&.wiki) || false
      wiki ? "pick_wiki_#{name}" : "pick_#{name}"
    }
    "#{req.link("/battle")}?#{param.call(a)}=on&#{param.call(b)}=on&seed=#{seed}"
  end
end
