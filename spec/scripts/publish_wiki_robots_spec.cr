require "../spec_helper"

# Exercises scripts/publish_wiki_robots.sh for real, but against a
# throwaway Fossil repository created just for this spec, not the
# shared repository this checkout itself lives in -- publishing is a
# real write (fossil wiki create/commit), so this proves the script
# works without touching the wiki pages CrystalRobots::Web::WikiRobots
# reads from elsewhere in this suite.
describe "scripts/publish_wiki_robots.sh" do
  it "creates a robot/<name> wiki page per robots/*.md, and updates it on a second run" do
    repo = File.tempname("publish_wiki_robots_spec", ".fossil")
    begin
      init = Process.run("fossil", ["init", repo, "-A", "tester"], env: {"USER" => "tester"},
        output: IO::Memory.new, error: (init_err = IO::Memory.new))
      init.success?.should be_true, init_err.to_s

      first = Process.run("sh", ["scripts/publish_wiki_robots.sh", "-R", repo], env: {"USER" => "tester"},
        output: (first_out = IO::Memory.new), error: IO::Memory.new)
      first.success?.should be_true
      first_out.to_s.should contain "created robot/hunter"

      names_out = IO::Memory.new
      Process.run("fossil", ["wiki", "list", "-R", repo], env: {"USER" => "tester"}, output: names_out, error: IO::Memory.new)
      names = names_out.to_s.lines.map(&.strip)
      {"robot/circler", "robot/dodger", "robot/hunter", "robot/turret", "robot/wallhugger"}.each do |name|
        names.should contain name
      end

      exported = IO::Memory.new
      Process.run("fossil", ["wiki", "export", "robot/hunter", "-", "-R", repo], env: {"USER" => "tester"}, output: exported, error: IO::Memory.new)
      exported.to_s.should eq File.read("robots/hunter.md")

      second = Process.run("sh", ["scripts/publish_wiki_robots.sh", "-R", repo], env: {"USER" => "tester"},
        output: (second_out = IO::Memory.new), error: IO::Memory.new)
      second.success?.should be_true
      second_out.to_s.should contain "updated robot/hunter"
    ensure
      File.delete(repo) if File.exists?(repo)
    end
  end
end
