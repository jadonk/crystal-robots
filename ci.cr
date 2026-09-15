# The one CI command: everything the task pipeline, trunk-ops and a
# developer run before trusting a revision. Exits non-zero on any failure.
# Crystal, not shell, per the convention Ollama-Codex adopted: `ci.cr` at
# the repository root, run with `crystal run`, replaces `scripts/ci.sh`.
#
#   crystal run ci.cr                    # build docs, build, spec, format, examples
#   crystal run ci.cr -- --with-wasmer   # also run the WebAssembly specs under wasmer 4.4.0,
#                                        # installing it under ./.wasmer when absent
#
# Without --with-wasmer the wasmer specs are reported as pending with their
# reason; they are never a tolerated failure.
require "file_utils"

class CI
  class Failed < Exception
  end

  def initialize
    @root = __DIR__
    @with_wasmer = false
  end

  def run(argv : Array(String)) : Nil
    argv.each do |arg|
      case arg
      when "--with-wasmer" then @with_wasmer = true
      else
        STDERR.puts "unknown option: #{arg}"
        exit 2
      end
    end
    Dir.cd(@root)

    step "shards install"
    unless quiet?("shards", ["install", "--without-development"])
      sh!("shards", ["install"])
    end

    step "bootstrap build"
    sh!("shards", ["build"])

    step "build-docs (before the final build, so the binary embeds them)"
    sh!("bin/crystal-robots", ["build-docs"])

    step "check manifest.uuid"
    check_manifest!

    step "shards build"
    sh!("shards", ["build"])

    spec_flags = [] of String
    if @with_wasmer
      step "wasmer 4.4.0"
      install_wasmer!
      spec_flags = ["-Dwasmer"]
    end

    step "crystal spec #{spec_flags.join(' ')}"
    sh!("crystal", ["spec"] + spec_flags)

    step "crystal tool format --check"
    sh!("crystal", ["tool", "format", "--check", "src", "spec", "scripts", "ci.cr"])

    step "example robots build natively with the prelude"
    build_examples!

    step "CLI smoke"
    smoke!

    puts "\n== ci.cr: all green#{@with_wasmer ? " (with wasmer)" : ""}"
  end

  private def step(message : String) : Nil
    puts "\n== #{message}"
  end

  # Runs a command with its output discarded, true only on success; used to
  # try the fast path before falling back to a visible, failing run.
  private def quiet?(command : String, args : Array(String)) : Bool
    Process.run(command, args, output: Process::Redirect::Close, error: Process::Redirect::Close).success?
  end

  private def sh!(command : String, args : Array(String) = [] of String, dir : String? = nil) : Nil
    status = Process.run(command, args, chdir: dir, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
    raise Failed.new("#{command} #{args.join(' ')} failed (exit #{status.exit_code})") unless status.success?
  end

  private def sh_quiet!(command : String, args : Array(String) = [] of String) : Nil
    status = Process.run(command, args, output: Process::Redirect::Close, error: Process::Redirect::Inherit)
    raise Failed.new("#{command} #{args.join(' ')} failed (exit #{status.exit_code})") unless status.success?
  end

  # Without it the shipped binary reports "unknown" for --version and
  # /version, which defeats comparing a deploy against trunk, so the release
  # build (this one) refuses to ship that way; `crystal build`/`shards
  # build` run by hand outside ci.cr still fall back to "unknown", which is
  # fine for local dev.
  private def check_manifest! : Nil
    path = File.join(@root, "manifest.uuid")
    return if File.exists?(path) && File.size(path) > 0
    STDERR.puts "manifest.uuid is missing or empty; run 'fossil setting manifest on' and check out from Fossil so the release build carries a check-in"
    exit 1
  end

  # Every write stays inside the checkout: the installer appends its shell
  # snippet to $PROFILE (when that file exists), downloads through
  # mktemp -t (honours $TMPDIR), and prompts if a stale bin/wasmer is found,
  # so a partial install is cleared first.
  private def install_wasmer! : Nil
    dir = File.join(@root, ".wasmer")
    ENV["WASMER_DIR"] = dir
    bin = File.join(dir, "bin", "wasmer")
    libwasmer = File.join(dir, "lib", "libwasmer.a")
    unless File.exists?(bin) && File::Info.executable?(bin) && File.exists?(libwasmer)
      FileUtils.rm_rf(dir)
      FileUtils.mkdir_p(File.join(dir, "tmp"))
      File.write(File.join(dir, "profile.sh"), "")
      env = {
        "PROFILE"            => File.join(dir, "profile.sh"),
        "TMPDIR"             => File.join(dir, "tmp"),
        "WASMER_INSTALL_LOG" => "quiet",
      }
      status = Process.run("sh", ["scripts/install_wasmer.sh", "v4.4.0"], env: env,
        output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
      raise Failed.new("wasmer install failed (exit #{status.exit_code})") unless status.success?
      FileUtils.rm_rf(File.join(dir, "tmp"))
    end
    ENV["PATH"] = "#{File.join(dir, "bin")}:#{ENV["PATH"]}"
    sh!(File.join(dir, "bin", "wasmer"), ["--version"])
  end

  private def build_examples! : Nil
    FileUtils.mkdir_p("bin")
    Dir.glob("examples/*.cr").sort.each do |robot|
      name = File.basename(robot, ".cr")
      sh!("crystal", ["build", "--prelude=../src/prelude", "#{name}.cr", "-o", "../bin/example-#{name}"], dir: "examples")
    end
  end

  private def smoke! : Nil
    sh_quiet!("bin/crystal-robots", ["-v"])
    sh_quiet!("bin/crystal-robots", ["-t", "examples/test.cr"])
    sh!("bin/crystal-robots", ["-c", "examples/test.cr", "-o", "bin/test.wasm"])
    sh_quiet!("bin/crystal-robots", ["-m", "1", "-l", "3000", "examples/counter.cr", "examples/target.cr"])
  end
end

begin
  CI.new.run(ARGV)
rescue e : CI::Failed
  STDERR.puts "\nci.cr: #{e.message}"
  exit 1
end
