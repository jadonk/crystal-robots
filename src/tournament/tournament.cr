# The Tournament: pool play (round-robin, win +1 / loss -1, refight on no
# winner or on a points tie) followed by a single-elimination bracket
# (best-of-3, byes for the highest seeds). Designed by the bash user on the
# wiki page "Tournament ideas".
#
# This engine knows nothing about Battle::Field: it takes a `fight` proc
# `(entries, seed, limit) -> winner name or nil` so specs can use a fake and
# the web layer can plug CrystalRobots::Battle::Field. A Ladder is the full
# result (pools with standings, bracket rounds with fights, champion) and
# round-trips through a URL query, so any tournament page is reproducible
# from its link.
require "uri"

module CrystalRobots::Tournament
  # A single fight attempt: entrants, the seed it ran with, and the winner's
  # name (nil = no winner, a draw or the cycle limit with 2+ survivors).
  alias FightFn = Proc(Array(String), UInt64, Int32, String?)

  # A no-winner fight is retried with the next seed, up to this many tries,
  # then it counts as 0-0 (pool points) or a drawn game (bracket).
  RETRY_LIMIT = 3

  record FightRecord, entrants : Array(String), seed : UInt64, winner : String?
  record Standing, name : String, points : Int32, rank : Int32
  record PoolResult, entrants : Array(String), fights : Array(FightRecord), standings : Array(Standing)
  record BracketMatch, entrants : Array(String?), games : Array(FightRecord), winner : String
  record Round, label : String, matches : Array(BracketMatch)

  record Ladder, entrants : Array(String), seed : UInt64, limit : Int32, format : String,
    pools : Array(PoolResult), rounds : Array(Round), champion : String do
    # Total Battle::Field runs across the whole tournament, including
    # refight retries, so a caller can budget cycles per HTTP request.
    def fight_count : Int32
      pools.sum(&.fights.size) + rounds.sum { |r| r.matches.sum { |m| m.games.size } }
    end

    def to_query : String
      URI::Params.build do |form|
        entrants.each { |name| form.add("names", name) }
        form.add("seed", seed.to_s)
        form.add("limit", limit.to_s)
        form.add("format", format)
      end
    end

    def self.from_query(query : String, fight : FightFn) : Ladder
      params = URI::Params.parse(query)
      names = params.fetch_all("names")
      seed = params["seed"].to_u64
      limit = params["limit"].to_i32
      format = params.fetch("format", "html")
      Tournament.run(names, seed, limit, fight, format)
    end
  end

  # A running seed cursor: every fight attempt (a fresh pairing, a refight,
  # a bracket game) draws the next seed in one shared sequence, so a
  # no-winner fight is always refought at "the next seed".
  private class Cursor
    def initialize(@value : UInt64)
    end

    def next! : UInt64
      v = @value
      @value = @value &+ 1
      v
    end

    # The seed the next `next!` would hand out, without consuming it: lets
    # a caller resume a fresh Cursor exactly where this one left off.
    def peek : UInt64
      @value
    end
  end

  # Pool sizes for `n` entrants: 5 or fewer is one pool; otherwise pools of
  # 4 with the remainder folded into pools of 3 (9 -> 3+3+3, 10 -> 4+3+3,
  # 11 -> 4+4+3).
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

  # Groups `entrants` into pools in the given order (the designer decides
  # the order; nothing here shuffles it). `seed` is not needed for the
  # grouping itself, only kept so the call site reads `plan(entrants, seed)`
  # as the design describes it.
  def self.plan(entrants : Array(String), seed : UInt64) : Array(Array(String))
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
  # seeds, stopping at the first winner. Every attempt is appended to `log`
  # (so cycle cost is fully accounted), and the seed of the deciding (or
  # final) attempt is returned alongside the winner.
  private def self.decide(entries : Array(String), cursor : Cursor, limit : Int32, fight : FightFn, log : Array(FightRecord)) : {String?, UInt64}
    winner = nil
    seed_used = 0_u64
    RETRY_LIMIT.times do
      seed_used = cursor.next!
      winner = fight.call(entries, seed_used, limit)
      log << FightRecord.new(entries, seed_used, winner)
      break if winner
    end
    {winner, seed_used}
  end

  # Ranks pool members by points, descending; a tie in points is broken by
  # a mini round-robin among the tied names (using the same refight rule),
  # recursively, until the depth guard kicks in and falls back to the
  # original (stable) relative order to guarantee termination.
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
      winner, _ = decide([a, b], cursor, limit, fight, log)
      case winner
      when a then sub_points[a] += 1; sub_points[b] -= 1
      when b then sub_points[b] += 1; sub_points[a] -= 1
      end
    end
    rank(tied, sub_points, cursor, limit, fight, log, depth + 1)
  end

  # Round-robin: every pair fights once (win +1, loss -1, no-winner ->
  # refight, then 0 each), then the standings are ranked with tie-breaks.
  def self.play_pool(pool : Array(String), cursor : Cursor, limit : Int32, fight : FightFn) : PoolResult
    log = [] of FightRecord
    points = Hash(String, Int32).new(0)
    pool.each { |p| points[p] = 0 }
    pairs(pool).each do |(a, b)|
      winner, _ = decide([a, b], cursor, limit, fight, log)
      case winner
      when a then points[a] += 1; points[b] -= 1
      when b then points[b] += 1; points[a] -= 1
      end
    end
    order = rank(pool, points, cursor, limit, fight, log)
    standings = order.map_with_index { |name, i| Standing.new(name, points[name], i + 1) }
    PoolResult.new(pool, log, standings)
  end

  # Who advances to the bracket, already in seed order (seed 1 = best):
  # one pool -> top three (2nd vs 3rd meets 1st in the final, via the bye
  # below); 2+ pools -> all pool winners (in pool order) then all
  # runners-up (in pool order), so the standard bracket pairing below
  # produces "1A vs 2B, 1B vs 2A" for two pools.
  def self.advancers(pools : Array(PoolResult)) : Array(String)
    if pools.size == 1
      pools[0].standings.first(3).map(&.name)
    else
      firsts = pools.map { |p| p.standings[0].name }
      seconds = pools.map { |p| p.standings[1].name }
      firsts + seconds
    end
  end

  private def self.next_pow2(n : Int32) : Int32
    p = 1
    while p < n
      p *= 2
    end
    p
  end

  # The standard seeded-bracket slot order (1 vs N, 2 vs N-1, ... without
  # ever meeting seed 2 before the final): for n=4, [1,4,2,3]; for n=8,
  # [1,8,4,5,2,7,3,6].
  private def self.seed_order(n : Int32) : Array(Int32)
    return [1] if n <= 1
    seed_order(n // 2).flat_map { |s| [s, n + 1 - s] }
  end

  # Seeds beyond `advancers.size` are byes (nil): with 3 advancers this
  # naturally produces "2 vs 3, winner vs 1" (seed 1 gets the bye); with 6
  # advancers in an 8-slot bracket, seeds 1 and 2 (the highest seeds) get
  # the byes.
  private def self.bracket_slots(advancers : Array(String), size : Int32) : Array(String?)
    seed_order(size).map { |s| s <= advancers.size ? advancers[s - 1] : nil }
  end

  # One bracket match: a bye (one slot empty) auto-advances the other
  # entrant with no games played; otherwise best-of-3 at seeds s, s+1, s+2
  # (a no-winner game is refought at the next seed, same retry rule). A
  # match still tied after 3 games is broken by one more decisive fight,
  # falling back to the first-listed (higher-seeded) entrant if that, too,
  # has no winner after its retries.
  def self.play_match(a : String?, b : String?, cursor : Cursor, limit : Int32, fight : FightFn) : BracketMatch
    log = [] of FightRecord
    if a.nil? || b.nil?
      winner = a || b || raise ArgumentError.new("bracket match with both slots empty")
      return BracketMatch.new([a, b], log, winner)
    end
    wins = Hash(String, Int32).new(0)
    3.times do
      winner, _ = decide([a, b], cursor, limit, fight, log)
      wins[winner] += 1 if winner
    end
    winner = if wins[a] > wins[b]
               a
             elsif wins[b] > wins[a]
               b
             else
               w, _ = decide([a, b], cursor, limit, fight, log)
               w || a
             end
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

  # Single-elimination bracket from a seed-ordered list of advancers, with
  # byes for the highest seeds when the count is not a power of two.
  def self.play_bracket(advancers : Array(String), cursor : Cursor, limit : Int32, fight : FightFn) : Array(Round)
    size = next_pow2(advancers.size)
    total_rounds = 0
    s = size
    while s > 1
      s //= 2
      total_rounds += 1
    end
    current = bracket_slots(advancers, size)
    rounds = [] of Round
    index = 0
    while current.size > 1
      matches = current.each_slice(2).to_a.map { |pair| play_match(pair[0], pair[1], cursor, limit, fight) }
      rounds << Round.new(round_label(total_rounds, index), matches)
      current = matches.map { |m| m.winner.as(String?) }
      index += 1
    end
    rounds
  end

  # Runs the whole tournament: plan the pools, play them, advance the
  # winners into a bracket, play it out to a champion.
  def self.run(entrants : Array(String), seed : UInt64, limit : Int32, fight : FightFn, format : String = "html") : Ladder
    raise ArgumentError.new("a tournament needs at least 3 entrants") if entrants.size < 3
    cursor = Cursor.new(seed)
    pools = plan(entrants, seed).map { |pool| play_pool(pool, cursor, limit, fight) }
    rounds = play_bracket(advancers(pools), cursor, limit, fight)
    champion = rounds.last.matches.first.winner
    Ladder.new(entrants, seed, limit, format, pools, rounds, champion)
  end

  # --- Staged execution -----------------------------------------------
  #
  # `run` above plays a whole tournament, pools through champion, in one
  # call: fine for specs, but a stateless link-driven web UI must budget
  # Battle::Field cycles per HTTP request and must not re-run (and re-pay
  # for) fights it already decided on an earlier request. These entry
  # points play exactly one stage — the pools, or one bracket round — and
  # hand back `resume_seed`, the point a following stage's fresh Cursor
  # must start at to continue the same seed sequence `run` would have
  # used, so the same tournament always plays out identically whether it
  # is run in one call or staged across many.

  record PoolStage, pools : Array(PoolResult), advancers : Array(String), resume_seed : UInt64
  record RoundStage, round : Round, next_slots : Array(String?), resume_seed : UInt64, final : Bool

  # The pool-play stage: always the tournament's first stage.
  def self.play_pools(entrants : Array(String), seed : UInt64, limit : Int32, fight : FightFn) : PoolStage
    raise ArgumentError.new("a tournament needs at least 3 entrants") if entrants.size < 3
    cursor = Cursor.new(seed)
    pools = plan(entrants, seed).map { |pool| play_pool(pool, cursor, limit, fight) }
    PoolStage.new(pools, advancers(pools), cursor.peek)
  end

  # The bracket's seed-ordered starting slots (nil = bye) for `advancers`,
  # and how many rounds it takes to a champion: computed once, up front,
  # so a caller can drive `play_bracket_round` one round at a time and
  # still label each round correctly (Final, Semifinal, ...).
  def self.bracket_plan(advancers : Array(String)) : {Array(String?), Int32}
    size = next_pow2(advancers.size)
    total_rounds = 0
    s = size
    while s > 1
      s //= 2
      total_rounds += 1
    end
    {bracket_slots(advancers, size), total_rounds}
  end

  # Plays exactly one bracket round from `slots` (seed order, nil = bye),
  # resuming the seed cursor at `seed`. `final` is true once this round
  # leaves a single winner (the champion).
  def self.play_bracket_round(slots : Array(String?), seed : UInt64, limit : Int32, fight : FightFn, total_rounds : Int32, index : Int32) : RoundStage
    cursor = Cursor.new(seed)
    matches = slots.each_slice(2).to_a.map { |pair| play_match(pair[0], pair[1], cursor, limit, fight) }
    next_slots = matches.map { |m| m.winner.as(String?) }
    RoundStage.new(Round.new(round_label(total_rounds, index), matches), next_slots, cursor.peek, next_slots.size <= 1)
  end
end
