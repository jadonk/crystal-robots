# Pool play, the first half of the Tournament designed on the wiki page
# "Tournament ideas": pools of 4 (3 when the numbers do not come out
# even), everyone in a pool fights everyone else once, a win is +1 and
# a loss is -1, and a fight with no winner is refought at the next seed
# rather than counted at all.
#
# This engine knows nothing about Battle::Field: it takes a `fight`
# proc `(entries, seed, limit) -> winner name or nil`, so specs can use
# a fake and the web layer can plug in a real match. The bracket half
# of the Tournament is a later commit.
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
  # and who advances, in seed order. The bracket that follows is a
  # later commit.
  def self.play_pools(entrants : Array(String), seed : Int32, limit : Int32, fight : FightFn) : Array(PoolResult)
    raise ArgumentError.new("a tournament needs at least 3 entrants") if entrants.size < 3
    cursor = Cursor.new(seed)
    plan(entrants).map { |pool| play_pool(pool, cursor, limit, fight) }
  end
end
