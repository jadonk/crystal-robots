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
end
