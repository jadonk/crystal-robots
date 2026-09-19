require "./spec_helper"
require "../src/version"

describe "crystal-robots CLI" do
  it "builds and reports its version and check-in" do
    output = `crystal run src/cli.cr -- --version`
    output.chomp.should eq CrystalRobots.version_line
    output.should contain CrystalRobots::VERSION
  end

  it "-t prints the parse derivation for an example robot" do
    output = `crystal run src/cli.cr -- -t examples/hello.cr`
    output.should contain "∊№⏎"
    output.should contain "⏹"
  end

  it "-k reports no issues for a clean robot, and the problem for a broken one" do
    ok = `crystal run src/cli.cr -- -k examples/functions.cr`
    ok.chomp.should eq "no issues found"

    File.write("/tmp/crystal-robots-cli-spec-bad.cr", "puts mystery\n")
    bad = `crystal run src/cli.cr -- -k /tmp/crystal-robots-cli-spec-bad.cr`
    bad.should contain "undefined variable mystery"
  end

  it "-i interprets and prints a robot's puts output" do
    output = `crystal run src/cli.cr -- -i examples/functions.cr`
    output.should eq "5\n30\n35\n"
  end

  it "-c -o compiles to a WebAssembly module that wasmer accepts" do
    out_file = "/tmp/crystal-robots-cli-spec.wasm"
    system("crystal run src/cli.cr -- -c examples/functions.cr -o #{out_file}").should be_true
    File.exists?(out_file).should be_true
    File.read(out_file)[0, 4].bytes.should eq [0x00, 0x61, 0x73, 0x6D]
  end

  it "-d compiles and prints a readable instruction dump" do
    output = `crystal run src/cli.cr -- -d examples/hello.cr`
    output.should contain "import env.puts"
    output.should contain "i32_const 42"
    output.should contain "call 0"
  end

  it "-m runs a seeded match between two robots and reports the outcome" do
    output = `crystal run src/cli.cr -- -m 2 -l 500 --seed 3 examples/target.cr examples/rabbit.cr`
    output.should contain "match 1:"
    output.should contain "match 2:"
    output.should contain "score:"
    output.should contain "target:"
    output.should contain "rabbit:"
  end
end
