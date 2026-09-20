require "./spec_helper"
require "../src/tournament/tournament"

alias T = CrystalRobots::Tournament

# A fake fight function: call index `i` (0-based, in the order the engine
# calls it) either follows `overrides[i]` (a winner name, or nil for a
# no-winner fight) or, when `i` is not overridden, `entries[0]` wins. The
# engine's seed cursor advances exactly one seed per call, so call index and
# seed offset from the tournament's seed always coincide.
private def scripted_fight(overrides : Hash(Int32, String?)) : T::FightFn
  i = 0
  ->(entries : Array(String), seed : UInt64, limit : Int32) {
    idx = i
    i += 1
    overrides.has_key?(idx) ? overrides[idx] : entries[0]
  }
end

private def default_fight : T::FightFn
  scripted_fight({} of Int32 => String?)
end

describe CrystalRobots::Tournament do
  describe ".pool_sizes" do
    it "makes one pool for 5 or fewer entrants" do
      T.pool_sizes(3).should eq [3]
      T.pool_sizes(4).should eq [4]
      T.pool_sizes(5).should eq [5]
    end

    it "splits larger fields into pools of 4 or 3" do
      T.pool_sizes(6).should eq [3, 3]
      T.pool_sizes(7).should eq [4, 3]
      T.pool_sizes(8).should eq [4, 4]
      T.pool_sizes(9).should eq [3, 3, 3]
      T.pool_sizes(10).should eq [4, 3, 3]
      T.pool_sizes(11).should eq [4, 4, 3]
      T.pool_sizes(12).should eq [4, 4, 4]
    end
  end

  describe ".plan" do
    it "groups entrants in the given order, not shuffled" do
      names = (1..10).map { |i| "e#{i}" }
      pools = T.plan(names, 1_u64)
      pools.map(&.size).should eq [4, 3, 3]
      pools.flatten.should eq names
    end
  end

  describe "pool play" do
    it "scores a win +1 and a loss -1 with no ties" do
      names = ["X", "Y", "Z"]
      ladder = T.run(names, 1_u64, 100, default_fight)
      pool = ladder.pools[0]
      pool.standings.map(&.name).should eq ["X", "Y", "Z"]
      pool.standings.map(&.points).should eq [2, 0, -2]
      pool.standings.map(&.rank).should eq [1, 2, 3]
    end

    it "refights a no-winner fight at the next seed" do
      names = ["P", "Q", "R"]
      overrides = {0 => nil} of Int32 => String?
      ladder = T.run(names, 5_u64, 100, scripted_fight(overrides))
      pool = ladder.pools[0]
      pool.fights[0].winner.should be_nil
      pool.fights[0].seed.should eq 5_u64
      pool.fights[1].winner.should eq "P" # refought at seed+1
      pool.fights[1].seed.should eq 6_u64
      pool.standings.find { |s| s.name == "P" }.not_nil!.points.should eq 2
      pool.standings.find { |s| s.name == "Q" }.not_nil!.points.should eq 0
      pool.standings.find { |s| s.name == "R" }.not_nil!.points.should eq -2
    end

    it "scores 0-0 after 3 no-winner tries" do
      names = ["S", "T", "U"]
      overrides = {0 => nil, 1 => nil, 2 => nil, 3 => "U"} of Int32 => String?
      ladder = T.run(names, 9_u64, 100, scripted_fight(overrides))
      pool = ladder.pools[0]
      st_fights = pool.fights.first(3)
      st_fights.map(&.winner).should eq [nil, nil, nil]
      st_fights.map(&.seed).should eq [9_u64, 10_u64, 11_u64]
      pool.standings.find { |s| s.name == "S" }.not_nil!.points.should eq -1
      pool.standings.find { |s| s.name == "T" }.not_nil!.points.should eq 1
      pool.standings.find { |s| s.name == "U" }.not_nil!.points.should eq 0
    end

    it "breaks two simultaneous points ties with a refight" do
      names = ["A", "B", "C", "D"]
      overrides = {2 => "D", 4 => "D", 6 => "D", 7 => "C"} of Int32 => String?
      ladder = T.run(names, 1_u64, 100, scripted_fight(overrides))
      pool = ladder.pools[0]
      pool.standings.map(&.name).should eq ["D", "A", "C", "B"]
      pool.standings.map(&.points).should eq [1, 1, -1, -1]
      pool.standings.map(&.rank).should eq [1, 2, 3, 4]
      pool.fights.size.should eq 8 # 6 round-robin + 2 tie-break refights
    end
  end

  describe "the bracket" do
    it "builds the 3-entrant bracket: 2nd vs 3rd, winner meets 1st in the final" do
      names = ["X", "Y", "Z"]
      ladder = T.run(names, 1_u64, 100, default_fight)
      ladder.rounds.size.should eq 2
      ladder.rounds[0].label.should eq "Semifinal"
      ladder.rounds[1].label.should eq "Final"

      bye, second = ladder.rounds[0].matches
      bye.entrants.should eq ["X", nil] # X vs an empty slot (a bye)
      bye.games.should be_empty
      bye.winner.should eq "X"
      second.entrants.should eq ["Y", "Z"]
      second.games.size.should eq 2 # Y wins the first two games 2-0, no third game needed
      second.winner.should eq "Y"

      final = ladder.rounds[1].matches[0]
      final.entrants.should eq ["X", "Y"]
      final.winner.should eq "X"
      ladder.champion.should eq "X"
      ladder.fight_count.should eq 7 # 3 pool fights + 0 (bye) + 2 + 2 bracket games
    end

    it "gives the highest seeds byes in a quarter round for 6 advancers" do
      names = (0..8).map { |i| "E#{i}" } # 9 entrants -> 3 pools of 3
      ladder = T.run(names, 1_u64, 100, default_fight)
      ladder.rounds.size.should eq 3
      ladder.rounds[0].label.should eq "Quarterfinal"
      ladder.rounds[1].label.should eq "Semifinal"
      ladder.rounds[2].label.should eq "Final"

      qf = ladder.rounds[0].matches
      qf.size.should eq 4
      # each pool of [Ei, Ei+1, Ei+2] under "entries[0] always wins" ranks
      # Ei 1st, Ei+1 2nd; the two pool winners with the earliest pools are
      # the highest seeds and get the byes.
      qf[0].games.should be_empty
      qf[0].winner.should eq "E0"
      qf[2].games.should be_empty
      qf[2].winner.should eq "E3"
      qf[1].games.size.should eq 2 # 2-0, no third game needed
      qf[3].games.size.should eq 2

      ladder.champion.should eq "E0"
      ladder.fight_count.should eq 19 # 3 pools * 3 fights + (0+2+0+2) qf + (2+2) semi + 2 final
    end

    it "caps a match's total refights at RETRY_LIMIT, like a pool pairing, instead of retrying each game independently" do
      names = ["P", "Q"]
      # not a real tournament (too few entrants), so exercise play_match
      # indirectly is not possible from outside the module; instead drive a
      # 3-entrant tournament where the semifinal is exactly this match.
      overrides = {3 => nil, 4 => nil, 5 => nil} of Int32 => String? # every attempt in the Y vs Z match is a no-winner
      ladder = T.run(["X", "Y", "Z"], 1_u64, 100, scripted_fight(overrides))
      match = ladder.rounds[0].matches[1]
      match.entrants.should eq ["Y", "Z"]
      match.games.map(&.winner).should eq [nil, nil, nil]
      match.games.size.should eq 3 # RETRY_LIMIT total attempts, not up to 3 games x 3 retries each
      match.winner.should eq "Y"   # tied 0-0 after the shared budget: the higher (first-listed) seed advances
    end

    it "settles a match early once an entrant reaches 2 wins, without spending the full retry budget" do
      overrides = {3 => "Z", 4 => "Z"} of Int32 => String? # Z wins the Y vs Z match's first two attempts
      ladder = T.run(["X", "Y", "Z"], 1_u64, 100, scripted_fight(overrides))
      match = ladder.rounds[0].matches[1]
      match.entrants.should eq ["Y", "Z"]
      match.games.map(&.winner).should eq ["Z", "Z"]
      match.winner.should eq "Z"
    end
  end

  describe "URL round-trip" do
    it "reproduces the same ladder from names + seed + limit + format" do
      names = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf"]
      ladder = T.run(names, 42_u64, 500, default_fight, "svg")
      query = ladder.to_query
      query.should contain "names=Alpha"
      query.should contain "seed=42"
      query.should contain "limit=500"
      query.should contain "format=svg"

      reloaded = T::Ladder.from_query(query, default_fight)
      reloaded.should eq ladder
    end
  end

  describe "staged execution" do
    it "plays pools then each bracket round to the same result as .run, one stage at a time" do
      names = (0..8).map { |i| "E#{i}" } # 9 entrants -> 3 pools of 3, matches the earlier bracket-byes spec
      whole = T.run(names, 1_u64, 100, default_fight)

      pool_stage = T.play_pools(names, 1_u64, 100, default_fight)
      pool_stage.pools.should eq whole.pools
      pool_stage.advancers.should eq T.advancers(whole.pools)

      slots, total_rounds = T.bracket_plan(pool_stage.advancers)
      total_rounds.should eq whole.rounds.size

      rounds = [] of T::Round
      seed = pool_stage.resume_seed
      current = slots
      total_rounds.times do |i|
        stage = T.play_bracket_round(current, seed, 100, default_fight, total_rounds, i)
        rounds << stage.round
        seed = stage.resume_seed
        current = stage.next_slots
        stage.final.should eq(i == total_rounds - 1)
      end
      rounds.should eq whole.rounds
      rounds.last.matches.first.winner.should eq whole.champion
    end

    it "rejects fewer than 3 entrants at the pool stage, like .run" do
      expect_raises(ArgumentError, "at least 3 entrants") do
        T.play_pools(["A", "B"], 1_u64, 100, default_fight)
      end
    end
  end
end
