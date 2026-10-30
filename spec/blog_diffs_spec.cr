require "./spec_helper"
require "yaml"
require "json"
require "file_utils"

BLOG_ROOT     = File.expand_path("..", __DIR__)
BLOG_CHROMIUM = if (configured = ENV["CHROMIUM_BIN"]?) && !configured.empty?
                  Process.find_executable(configured)
                else
                  Process.find_executable("chromium") || Process.find_executable("chromium-browser") || Process.find_executable("google-chrome")
                end

def blog_git(dir : String, *args : String)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run("git", args.to_a, chdir: dir, output: output, error: errors)
  status.success?.should be_true, "git #{args.join(" ")}: #{errors}"
  output.to_s.strip
end

def blog_build(dir : String)
  output = IO::Memory.new
  errors = IO::Memory.new
  status = Process.run("crystal", ["run", File.join(BLOG_ROOT, "scripts/build_blog_diffs.cr"), "--", "HEAD"], chdir: dir, output: output, error: errors)
  {status, output.to_s, errors.to_s}
end

describe "blog diff data" do
  it "builds a deterministic excerpt from a tiny two-commit repository and reports a missing anchor" do
    dir = File.join(Dir.tempdir, "blog-diffs-#{Process.pid}-#{Random.rand(1_000_000)}")
    Dir.mkdir_p(File.join(dir, "site/blog/diffs"))
    begin
      blog_git(dir, "init", "-q")
      blog_git(dir, "config", "user.name", "Test")
      blog_git(dir, "config", "user.email", "test@example.com")
      File.write(File.join(dir, "hello.cr"), "puts 1\n")
      blog_git(dir, "add", ".")
      blog_git(dir, "commit", "-qm", "Start")
      File.write(File.join(dir, "hello.cr"), "puts 2\n")
      blog_git(dir, "add", ".")
      blog_git(dir, "commit", "-qm", "Change number")
      File.write(File.join(dir, "site/blog/index.html"), %(<section class="commit" id="c-change"><a class="commit-link" data-subject="Change number"></a></section>))
      notes_path = File.join(dir, "site/blog/diffs/notes.yml")
      notes = %({"roles":{"hello.cr":"Example program."},"commits":{"c-change":{"summary":"Changes the printed number.","excerpts":[{"file":"hello.cr","anchor":"puts 2","note":"The new number is two."}]}}})
      File.write(notes_path, notes)
      status, _, errors = blog_build(dir)
      status.success?.should be_true, errors
      result_path = File.join(dir, "site/blog/diffs/c-change.json")
      first = File.read(result_path)
      result = JSON.parse(first)
      result["subject"].as_s.should eq("Change number")
      result["sha"].as_s.size.should eq(40)
      result["files"][0]["added"].as_i.should eq(1)
      result["excerpts"][0]["lines"].as_a.any? { |line| line["kind"].as_s == "+" && line["new"].as_i == 1 }.should be_true
      blog_build(dir)[0].success?.should be_true
      File.read(result_path).should eq(first)
      File.write(notes_path, notes.gsub("puts 2", "missing text"))
      status, _, errors = blog_build(dir)
      status.success?.should be_false
      errors.includes?("anchor").should be_true
      errors.includes?("missing text").should be_true
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "has notes and generated data for every chapter 1 view" do
    html = File.read(File.join(BLOG_ROOT, "site/blog/index.html"))
    notes = YAML.parse(File.read(File.join(BLOG_ROOT, "site/blog/diffs/notes.yml")))["commits"].as_h
    ids = html.scan(/data-diff="([^"]+)"/).map(&.[1])
    ids.size.should eq(16)
    ids.each do |id|
      notes.has_key?(YAML::Any.new(id)).should be_true
      File.exists?(File.join(BLOG_ROOT, "site/blog/diffs/#{id}.json")).should be_true
    end
  end
end

describe "blog diff views (headless)" do
  if (bin = BLOG_CHROMIUM) && Process.find_executable("node")
    it "renders every chapter 1 change, toggles by keyboard, and fits at 360px" do
      output = IO::Memory.new
      errors = IO::Memory.new
      status = Process.run("node", ["spec/support/blog_diffs_check.mjs", bin], output: output, error: errors)
      status.success?.should be_true, "blog_diffs_check.mjs failed: #{output}\n#{errors}"
      JSON.parse(output.to_s)["ok"].as_bool.should be_true
    end
  else
    pending "blog diff view needs node and a browser (CHROMIUM_BIN, chromium, chromium-browser, or google-chrome)"
  end
end
