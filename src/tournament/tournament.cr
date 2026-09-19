# Pool play, the first half of the Tournament designed on the wiki page
# "Tournament ideas": pools of 4 (3 when the numbers do not come out
# even), everyone in a pool fights everyone else once, a win is +1 and
# a loss is -1, and a fight with no winner is refought at the next seed
# rather than counted at all.
#
# This engine knows nothing about Battle::Field: it takes a `fight`
# proc `(entries, seed, limit) -> winner name or nil`, so specs can use
# a fake and the web layer can plug in a real match.
module CrystalRobots::Tournament
  # A single fight attempt: entrants, the seed it ran with, and the
  # winner's name (nil = no winner -- a draw, or the cycle limit
  # reached with more than one survivor).
  alias FightFn = Proc(Array(String), Int32, Int32, String?)

  # A no-winner fight is retried with the next seed, up to this many
  # tries total, then it counts as 0-0 -- the wiki page's answer to
  # "if a pool fight has no winner three times in a row": "yes" (both
  # robots get 0 points for it so the tournament can finish).
  RETRY_LIMIT = 3

  record FightRecord, entrants : Array(String), seed : Int32, winner : String?
  record Standing, name : String, points : Int32, rank : Int32
  record PoolResult, entrants : Array(String), fights : Array(FightRecord), standings : Array(Standing)

  # A running seed cursor: every fight attempt (a fresh pairing or a
  # refight) draws the next seed from one shared sequence, so a
  # no-winner fight is always refought at "the next seed", the wiki
  # page's own words for it.
  private class Cursor
    def initialize(@value : Int32)
    end

    def next! : Int32
      v = @value
      @value = @value &+ 1
      v
    end

    # The seed the next `next!` would hand out, without consuming it:
    # lets a caller resume a fresh Cursor exactly where this one left
    # off.
    def peek : Int32
      @value
    end
  end

  # Pool sizes for `n` entrants: 5 or fewer is one pool (the wiki
  # page's "Round 3" answer to the 5-robot case: one pool, top three
  # move on); otherwise pools of 4 with the remainder folded into
  # pools of 3 (9 -> 3+3+3, 10 -> 4+3+3, 11 -> 4+4+3), matching
  # "the pools should all have 4 or 3 robots".
  def self.pool_sizes(n : Int32) : Array(Int32)
    return [n] if n <= 5
    q, r = n.divmod(4)
    case r
    when 0 then Array.new(q, 4)
    when 1 then Array.new(q - 2, 4) + Array.new(3, 3)
    when 2 then Array.new(q - 1, 4) + Array.new(2, 3)
    else        Array.new(q, 4) + [3]
    end
  end

  # Groups `entrants` into pools in the given order; nothing here
  # shuffles it, the designer's own order decides the grouping.
  def self.plan(entrants : Array(String)) : Array(Array(String))
    pools = [] of Array(String)
    offset = 0
    pool_sizes(entrants.size).each do |size|
      pools << entrants[offset, size]
      offset += size
    end
    pools
  end

  # Every unordered pair from `items`, in the given order.
  private def self.pairs(items : Array(String)) : Array({String, String})
    result = [] of {String, String}
    items.each_with_index do |a, i|
      items[(i + 1)...items.size].each { |b| result << {a, b} }
    end
    result
  end

  # Runs one fight-with-refights: up to RETRY_LIMIT tries at successive
  # seeds, stopping at the first winner. Every attempt is appended to
  # `log`, so a pool's fight list shows every refight, not just the
  # deciding one.
  private def self.decide(entries : Array(String), cursor : Cursor, limit : Int32, fight : FightFn, log : Array(FightRecord)) : String?
    winner = nil
    RETRY_LIMIT.times do
      seed_used = cursor.next!
      winner = fight.call(entries, seed_used, limit)
      log << FightRecord.new(entries, seed_used, winner)
      break if winner
    end
    winner
  end

  # Ranks pool members by points, descending. A tie in points is
  # broken by a mini round-robin among the tied names (the same
  # refight rule), recursively, until a depth guard falls back to the
  # original relative order so ranking always terminates.
  private def self.rank(pool : Array(String), points : Hash(String, Int32), cursor : Cursor, limit : Int32, fight : FightFn, log : Array(FightRecord), depth : Int32 = 0) : Array(String)
    groups = pool.group_by { |name| points[name] }
    result = [] of String
    groups.keys.sort.reverse.each do |pts|
      tied = groups[pts]
      if tied.size == 1 || depth >= 3
        result.concat(tied)
      else
        result.concat(resolve_tie(tied, cursor, limit, fight, log, depth))
      end
    end
    result
  end

  private def self.resolve_tie(tied : Array(String), cursor : Cursor, limit : Int32, fight : FightFn, log : Array(FightRecord), depth : Int32) : Array(String)
    sub_points = Hash(String, Int32).new(0)
    tied.each { |p| sub_points[p] = 0 }
    pairs(tied).each do |(a, b)|
      case decide([a, b], cursor, limit, fight, log)
      when a then sub_points[a] += 1; sub_points[b] -= 1
      when b then sub_points[b] += 1; sub_points[a] -= 1
      end
    end
    rank(tied, sub_points, cursor, limit, fight, log, depth + 1)
  end

  # Round-robin: every pair fights once (win +1, loss -1, no-winner ->
  # refight then 0-0), then the standings are ranked with tie-breaks.
  def self.play_pool(pool : Array(String), cursor : Cursor, limit : Int32, fight : FightFn) : PoolResult
    log = [] of FightRecord
    points = Hash(String, Int32).new(0)
    pool.each { |p| points[p] = 0 }
    pairs(pool).each do |(a, b)|
      case decide([a, b], cursor, limit, fight, log)
      when a then points[a] += 1; points[b] -= 1
      when b then points[b] += 1; points[a] -= 1
      end
    end
    order = rank(pool, points, cursor, limit, fight, log)
    standings = order.map_with_index { |name, i| Standing.new(name, points[name], i + 1) }
    PoolResult.new(pool, log, standings)
  end

  # Who advances to the bracket, already in seed order (seed 1 = best):
  # one pool -> top three (the wiki page's 5-or-fewer answer); 2+ pools
  # -> every pool's winner (in pool order) then every runner-up (in
  # pool order), so a standard bracket pairing gives "1A vs 2B, 1B vs
  # 2A" for two pools.
  def self.advancers(pools : Array(PoolResult)) : Array(String)
    if pools.size == 1
      pools[0].standings.first(3).map(&.name)
    else
      firsts = pools.map { |p| p.standings[0].name }
      seconds = pools.map { |p| p.standings[1].name }
      firsts + seconds
    end
  end

  # Plays every pool for `entrants` from `seed`, returning the pools
  # and who advances, in seed order.
  def self.play_pools(entrants : Array(String), seed : Int32, limit : Int32, fight : FightFn) : Array(PoolResult)
    raise ArgumentError.new("a tournament needs at least 3 entrants") if entrants.size < 3
    cursor = Cursor.new(seed)
    plan(entrants).map { |pool| play_pool(pool, cursor, limit, fight) }
  end

  # --- The bracket ------------------------------------------------------
  #
  # Single elimination, seeded so the highest seeds meet last and the
  # highest seeds get byes when the field is not a power of two, best
  # of 3 per match -- the wiki page's own answer to "best of 3
  # everywhere, or only in the final?": "only in the bracket".

  record BracketMatch, entrants : Array(String?), games : Array(FightRecord), winner : String
  record Round, label : String, matches : Array(BracketMatch)

  private def self.next_pow2(n : Int32) : Int32
    p = 1
    while p < n
      p *= 2
    end
    p
  end

  # The standard seeded-bracket slot order (1 vs N, 2 vs N-1, ...
  # without seed 2 ever meeting seed 1 before the final): for n=4,
  # [1,4,2,3]; for n=8, [1,8,4,5,2,7,3,6].
  private def self.seed_order(n : Int32) : Array(Int32)
    return [1] if n <= 1
    seed_order(n // 2).flat_map { |s| [s, n + 1 - s] }
  end

  # Seeds beyond `advancers.size` are byes (nil): with 3 advancers
  # this gives "2 vs 3, winner vs 1" (seed 1 gets the bye, matching
  # the wiki page's 5-or-fewer answer exactly); with 6 advancers in
  # an 8-slot bracket, seeds 1 and 2 get the byes.
  private def self.bracket_slots(advancers : Array(String), size : Int32) : Array(String?)
    seed_order(size).map { |s| s <= advancers.size ? advancers[s - 1] : nil }
  end

  # One bracket match: a bye (one slot empty) auto-advances the other
  # entrant with no games played. Otherwise up to RETRY_LIMIT attempts
  # total -- the same shared budget a pool pairing gets, not a fresh
  # RETRY_LIMIT for each of up to 3 games -- stopping as soon as
  # either entrant reaches 2 wins. A match still tied (including 0-0,
  # every attempt a no-winner) after that budget is spent falls back
  # to the first-listed, higher-seeded entrant: this needs no further
  # information from a fight, the same way pool play's 0-0 does not,
  # unlike the wiki page's very first idea ("less damage wins").
  def self.play_match(a : String?, b : String?, cursor : Cursor, limit : Int32, fight : FightFn) : BracketMatch
    log = [] of FightRecord
    if a.nil? || b.nil?
      winner = a || b || raise ArgumentError.new("bracket match with both slots empty")
      return BracketMatch.new([a, b], log, winner)
    end
    wins = Hash(String, Int32).new(0)
    RETRY_LIMIT.times do
      seed_used = cursor.next!
      game_winner = fight.call([a, b], seed_used, limit)
      log << FightRecord.new([a, b], seed_used, game_winner)
      wins[game_winner] += 1 if game_winner
      break if wins[a] >= 2 || wins[b] >= 2
    end
    winner = wins[a] > wins[b] ? a : (wins[b] > wins[a] ? b : a)
    BracketMatch.new([a, b] of String?, log, winner)
  end

  private def self.round_label(total_rounds : Int32, index : Int32) : String
    case total_rounds - index
    when 1 then "Final"
    when 2 then "Semifinal"
    when 3 then "Quarterfinal"
    else        "Round of #{2 ** (total_rounds - index)}"
    end
  end

  private def self.total_rounds_for(advancer_count : Int32) : Int32
    size = next_pow2(advancer_count)
    total = 0
    while size > 1
      size //= 2
      total += 1
    end
    total
  end

  # --- Staged execution -----------------------------------------------
  #
  # A stateless, link-driven web UI must budget Battle::Field cycles
  # per HTTP request and must not re-run (and re-pay for) fights it
  # already decided on an earlier request. These entry points play
  # exactly one stage -- the pools, or one bracket round -- and hand
  # back the seed a following stage's fresh cursor must resume from,
  # so a tournament plays out identically whether run in one call or
  # staged across many requests.

  record RoundStage, round : Round, next_slots : Array(String?), resume_seed : Int32, final : Bool

  # The bracket's seed-ordered starting slots (nil = bye) for
  # `advancers`, and how many rounds it takes to reach a champion,
  # computed once so a caller can drive `play_bracket_round` one round
  # at a time and still label each round correctly.
  def self.bracket_plan(advancers : Array(String)) : {Array(String?), Int32}
    total_rounds = total_rounds_for(advancers.size)
    {bracket_slots(advancers, next_pow2(advancers.size)), total_rounds}
  end

  # Plays exactly one bracket round from `slots` (seed order, nil =
  # bye), resuming the seed cursor at `seed`. `final` is true once
  # this round leaves a single winner (the champion).
  def self.play_bracket_round(slots : Array(String?), seed : Int32, limit : Int32, fight : FightFn, total_rounds : Int32, index : Int32) : RoundStage
    cursor = Cursor.new(seed)
    matches = slots.each_slice(2).to_a.map { |pair| play_match(pair[0], pair[1], cursor, limit, fight) }
    next_slots = matches.map { |m| m.winner.as(String?) }
    RoundStage.new(Round.new(round_label(total_rounds, index), matches), next_slots, cursor.peek, next_slots.size <= 1)
  end

  # Runs a whole tournament in one call: pools, then the bracket to a
  # champion. Convenient for specs and for a caller with no per-request
  # cycle budget to respect; the web layer drives the staged entry
  # points above instead.
  def self.run(entrants : Array(String), seed : Int32, limit : Int32, fight : FightFn) : {Array(PoolResult), Array(Round), String}
    pools = play_pools(entrants, seed, limit, fight)
    slots, total_rounds = bracket_plan(advancers(pools))
    resume = seed + pools.sum(&.fights.size)
    rounds = [] of Round
    current = slots
    total_rounds.times do |i|
      stage = play_bracket_round(current, resume, limit, fight, total_rounds, i)
      rounds << stage.round
      resume = stage.resume_seed
      current = stage.next_slots
    end
    {pools, rounds, rounds.last.matches.first.winner}
  end
end
