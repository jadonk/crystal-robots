require "./spec_helper"
require "../src/version"

describe "crystal-robots CLI" do
  it "builds and reports its version" do
    output = `crystal run src/cli.cr -- --version`
    output.chomp.should eq "crystal-robots #{CrystalRobots::VERSION}"
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
end
