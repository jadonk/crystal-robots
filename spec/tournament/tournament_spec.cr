require "../spec_helper"

alias T = CrystalRobots::Tournament

# A fake fight function: call index `i` (0-based, in the order the
# engine calls it) either follows `overrides[i]` (a winner name, or
# nil for a no-winner fight) or, when `i` is not overridden,
# `entries[0]` wins. The engine's seed cursor advances exactly one
# seed per call, so call index and seed offset from the tournament's
# own starting seed always coincide.
private def scripted_fight(overrides : Hash(Int32, String?)) : T::FightFn
  i = 0
  ->(entries : Array(String), seed : Int32, limit : Int32) {
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
      pools = T.plan(names)
      pools.map(&.size).should eq [4, 3, 3]
      pools.flatten.should eq names
    end
  end

  describe ".play_pools" do
    it "rejects fewer than 3 entrants" do
      expect_raises(ArgumentError, "at least 3 entrants") do
        T.play_pools(["A", "B"], 1, 100, default_fight)
      end
    end

    it "scores a win +1 and a loss -1 with no ties" do
      names = ["X", "Y", "Z"]
      pools = T.play_pools(names, 1, 100, default_fight)
      pool = pools[0]
      pool.standings.map(&.name).should eq ["X", "Y", "Z"]
      pool.standings.map(&.points).should eq [2, 0, -2]
      pool.standings.map(&.rank).should eq [1, 2, 3]
    end

    it "refights a no-winner fight at the next seed" do
      names = ["P", "Q", "R"]
      overrides = {0 => nil} of Int32 => String?
      pool = T.play_pools(names, 5, 100, scripted_fight(overrides))[0]
      pool.fights[0].winner.should be_nil
      pool.fights[0].seed.should eq 5
      pool.fights[1].winner.should eq "P" # refought at seed+1
      pool.fights[1].seed.should eq 6
      pool.standings.find { |s| s.name == "P" }.not_nil!.points.should eq 2
      pool.standings.find { |s| s.name == "Q" }.not_nil!.points.should eq 0
      pool.standings.find { |s| s.name == "R" }.not_nil!.points.should eq -2
    end

    it "scores 0-0 after 3 no-winner tries, so the tournament can finish" do
      names = ["S", "T", "U"]
      overrides = {0 => nil, 1 => nil, 2 => nil, 3 => "U"} of Int32 => String?
      pool = T.play_pools(names, 9, 100, scripted_fight(overrides))[0]
      st_fights = pool.fights.first(3)
      st_fights.map(&.winner).should eq [nil, nil, nil]
      st_fights.map(&.seed).should eq [9, 10, 11]
      pool.standings.find { |s| s.name == "S" }.not_nil!.points.should eq -1
      pool.standings.find { |s| s.name == "T" }.not_nil!.points.should eq 1
      pool.standings.find { |s| s.name == "U" }.not_nil!.points.should eq 0
    end

    it "breaks a points tie with a refight among the tied names" do
      names = ["A", "B", "C", "D"]
      overrides = {2 => "D", 4 => "D", 6 => "D", 7 => "C"} of Int32 => String?
      pool = T.play_pools(names, 1, 100, scripted_fight(overrides))[0]
      pool.standings.map(&.name).should eq ["D", "A", "C", "B"]
      pool.standings.map(&.points).should eq [1, 1, -1, -1]
      pool.standings.map(&.rank).should eq [1, 2, 3, 4]
      pool.fights.size.should eq 8 # 6 round-robin + 2 tie-break refights
    end
  end

  describe ".advancers" do
    it "takes the top three from a single pool" do
      pools = T.play_pools(["X", "Y", "Z"], 1, 100, default_fight)
      T.advancers(pools).should eq ["X", "Y", "Z"]
    end

    it "takes every pool's winner, then every runner-up, in pool order" do
      names = (0..8).map { |i| "E#{i}" } # 9 entrants -> 3 pools of 3
      pools = T.play_pools(names, 1, 100, default_fight)
      T.advancers(pools).should eq ["E0", "E3", "E6", "E1", "E4", "E7"]
    end
  end

  describe ".run (pools then the bracket)" do
    it "builds the 3-entrant bracket: 2nd vs 3rd, winner meets 1st in the final" do
      names = ["X", "Y", "Z"]
      pools, rounds, champion = T.run(names, 1, 100, default_fight)
      rounds.size.should eq 2
      rounds[0].label.should eq "Semifinal"
      rounds[1].label.should eq "Final"

      bye, second = rounds[0].matches
      bye.entrants.should eq ["X", nil] # X vs an empty slot (a bye)
      bye.games.should be_empty
      bye.winner.should eq "X"
      second.entrants.should eq ["Y", "Z"]
      second.games.size.should eq 2 # Y wins the first two games 2-0, no third game needed
      second.winner.should eq "Y"

      final = rounds[1].matches[0]
      final.entrants.should eq ["X", "Y"]
      final.winner.should eq "X"
      champion.should eq "X"
      pools[0].fights.size.should eq 3
    end

    it "gives the highest seeds byes in a quarter round for 6 advancers" do
      names = (0..8).map { |i| "E#{i}" } # 9 entrants -> 3 pools of 3
      _, rounds, champion = T.run(names, 1, 100, default_fight)
      rounds.size.should eq 3
      rounds[0].label.should eq "Quarterfinal"
      rounds[1].label.should eq "Semifinal"
      rounds[2].label.should eq "Final"

      qf = rounds[0].matches
      qf.size.should eq 4
      # each pool of [Ei, Ei+1, Ei+2] under "entries[0] always wins" ranks
      # Ei 1st, Ei+1 2nd; the two pool winners from the earliest pools are
      # the highest seeds and get the byes.
      qf[0].games.should be_empty
      qf[0].winner.should eq "E0"
      qf[2].games.should be_empty
      qf[2].winner.should eq "E3"
      qf[1].games.size.should eq 2 # 2-0, no third game needed
      qf[3].games.size.should eq 2

      champion.should eq "E0"
    end

    it "caps a match's total refights at RETRY_LIMIT, like a pool pairing, instead of retrying each game independently" do
      overrides = {3 => nil, 4 => nil, 5 => nil} of Int32 => String? # every attempt in the Y vs Z semifinal is a no-winner
      _, rounds, _ = T.run(["X", "Y", "Z"], 1, 100, scripted_fight(overrides))
      match = rounds[0].matches[1]
      match.entrants.should eq ["Y", "Z"]
      match.games.map(&.winner).should eq [nil, nil, nil]
      match.games.size.should eq 3 # RETRY_LIMIT total attempts, not up to 3 games x 3 retries each
      match.winner.should eq "Y"   # tied 0-0 after the shared budget: the higher (first-listed) seed advances
    end

    it "settles a match early once an entrant reaches 2 wins, without spending the full retry budget" do
      overrides = {3 => "Z", 4 => "Z"} of Int32 => String? # Z wins the Y vs Z match's first two attempts
      _, rounds, _ = T.run(["X", "Y", "Z"], 1, 100, scripted_fight(overrides))
      match = rounds[0].matches[1]
      match.entrants.should eq ["Y", "Z"]
      match.games.map(&.winner).should eq ["Z", "Z"]
      match.winner.should eq "Z"
    end
  end

  describe "staged execution" do
    it "plays pools then each bracket round to the same result as .run, one stage at a time" do
      names = (0..8).map { |i| "E#{i}" } # 9 entrants -> 3 pools of 3
      whole_pools, whole_rounds, whole_champion = T.run(names, 1, 100, default_fight)

      pools = T.play_pools(names, 1, 100, default_fight)
      pools.should eq whole_pools
      advancers = T.advancers(pools)

      slots, total_rounds = T.bracket_plan(advancers)
      total_rounds.should eq whole_rounds.size

      rounds = [] of T::Round
      seed = 1 + pools.sum(&.fights.size)
      current = slots
      total_rounds.times do |i|
        stage = T.play_bracket_round(current, seed, 100, default_fight, total_rounds, i)
        rounds << stage.round
        seed = stage.resume_seed
        current = stage.next_slots
        stage.final.should eq(i == total_rounds - 1)
      end
      rounds.should eq whole_rounds
      rounds.last.matches.first.winner.should eq whole_champion
    end
  end
end
