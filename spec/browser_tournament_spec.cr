require "./spec_helper"
require "../src/browser"

private def tournament_report(request : String) : JSON::Any
  ptr = CrystalRobots::Browser.tournament_alloc(request.bytesize)
  ptr.copy_from(request.to_unsafe, request.bytesize)
  CrystalRobots::Browser.tournament_run
  JSON.parse(String.new(Bytes.new(CrystalRobots::Browser.tournament_result_ptr, CrystalRobots::Browser.tournament_result_len)))
end

private def tournament_robots : Array(NamedTuple(name: String, source: String))
  %w(sniper rook rabbit counter).map { |name| {name: name, source: File.read("examples/#{name}.cr")} }
end

private def replay_winner(fight : JSON::Any, sources : Hash(String, String), limit : Int64) : String?
  robots = fight["entrants"].as_a.map { |name| {name: name.as_s, source: sources[name.as_s]} }
  request = {robots: robots, seed: fight["seed"].as_i64, limit: limit}.to_json
  ptr = CrystalRobots::Browser.battle_alloc(request.bytesize)
  ptr.copy_from(request.to_unsafe, request.bytesize)
  CrystalRobots::Browser.battle_run
  JSON.parse(String.new(Bytes.new(CrystalRobots::Browser.battle_result_ptr, CrystalRobots::Browser.battle_result_len)))["winner"].as_s?
end

describe "CrystalRobots::Browser.tournament_run" do
  it "runs pools and a bracket, and records replayable fight seeds" do
    robots = tournament_robots
    report = tournament_report({robots: robots, seed: 3, limit: 3000}.to_json)
    report["error"]?.should be_nil
    report["entrants"].as_a.map(&.as_s).should eq robots.map(&.[:name])
    report["seed"].as_i.should eq 3
    report["limit"].as_i.should eq 3000
    report["rejected"].as_a.should be_empty
    report["pools"].as_a.size.should eq 1
    pool = report["pools"].as_a.first
    pool["entrants"].as_a.size.should eq 4
    pool["standings"].as_a.map { |s| s["rank"].as_i }.should eq [1, 2, 3, 4]
    report["rounds"].as_a.last["label"].as_s.should eq "Final"
    games = report["rounds"].as_a.flat_map { |r| r["matches"].as_a.flat_map { |m| m["games"].as_a } }
    report["fight_count"].as_i.should eq pool["fights"].as_a.size + games.size
    report["entrants"].as_a.map(&.as_s).includes?(report["champion"].as_s).should be_true

    sources = robots.to_h { |r| {r[:name], r[:source]} }
    pool_fight = pool["fights"].as_a.first
    replay_winner(pool_fight, sources, 3000_i64).should eq pool_fight["winner"].as_s?
    bracket_game = games.first
    replay_winner(bracket_game, sources, 3000_i64).should eq bracket_game["winner"].as_s?
  end

  it "rejects fewer than three robots" do
    report = tournament_report({robots: tournament_robots.first(2)}.to_json)
    report["error"].as_s.should contain "3 to 8"
  end

  it "rejects duplicate names" do
    robots = tournament_robots
    robots[1] = robots[1].merge({name: robots[0][:name]})
    report = tournament_report({robots: robots}.to_json)
    report["error"].as_s.should contain "duplicate"
  end

  it "reports a parse error and stops when only two valid entrants remain" do
    robots = tournament_robots.first(2) + [{name: "bad", source: "if x\n"}]
    report = tournament_report({robots: robots}.to_json)
    report["error"].as_s.should contain "at least 3 valid robots"
    report["entrants"].as_a.size.should eq 2
    report["rejected"].as_a.first["name"].as_s.should eq "bad"
    report["rejected"].as_a.first["error"].as_s.should contain "Cannot reduce"
  end

  it "keeps a rejected robot out of a valid tournament" do
    robots = tournament_robots + [{name: "bad", source: "if x\n"}]
    report = tournament_report({robots: robots, limit: 3000}.to_json)
    report["entrants"].as_a.size.should eq 4
    report["rejected"].as_a.first["name"].as_s.should eq "bad"
    report["rejected"].as_a.first["error"].as_s.should contain "Cannot reduce"
  end
end
