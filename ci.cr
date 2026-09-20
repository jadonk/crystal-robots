# The one CI command, written in Crystal: everything a developer, or a
# coordinator's own pipeline, runs before trusting a revision. Exits
# non-zero on any failure. Lives at the repo root, invoked as
# `crystal run ci.cr -- [flags]`, per the maintainer's direction that
# a shell script should not be the thing here -- this replaces
# scripts/ci.sh outright, not alongside it.
#
#   crystal run ci.cr --                  # build docs, build, spec, format
#   crystal run ci.cr -- --with-wasmer    # also run the WebAssembly specs under wasmer 4.4.0,
#                                         # installing it under ./.wasmer when absent
#   crystal run ci.cr -- --with-wasm32    # also build site/crystal-robots.wasm (the browser
#                                         # compiler) and run its specs; installs
#                                         # wasm32-wasi-libs under ./.wasm32-wasi-libs; needs
#                                         # `node` on PATH (its specs drive the module through
#                                         # site/wasi-shim.js, the same code the browser loads)
#
# Without --with-wasmer the wasmer specs are reported as pending with
# their own reason, and without --with-wasm32 the wasm32 specs are
# too; neither is ever a tolerated failure, only a signal this machine
# has no libwasmer, or hasn't built the browser compiler.
#
# `install_wasmer.sh` and `install_wasm32_wasi_libs.sh` stay shell
# scripts under scripts/: one is a vendored third-party installer, the
# other a plain tarball fetch-and-extract with no Crystal-specific
# logic, and rewriting either would just be duplicating a POSIX-only
# tool in a language that has to shell out to `tar`/`curl` anyway.
# `rm`, `git` and `sh` themselves are shelled out to for the same
# reason: this script orchestrates other tools, it does not reimplement
# a shell.
Dir.cd(__DIR__)

def step(msg : String) : Nil
  puts "\n== #{msg}"
end

def run!(command : String, args : Array(String) = [] of String, env : Process::Env = nil,
         output : Process::Redirect = Process::Redirect::Inherit,
         error : Process::Redirect = Process::Redirect::Inherit) : Nil
  status = Process.run(command, args, env: env, output: output, error: error)
  return if status.success?
  code = status.exit_code
  exit(code == 0 ? 1 : code)
end

def rm_rf(path : String) : Nil
  run!("rm", ["-rf", path])
end

with_wasmer = false
with_wasm32 = false
ARGV.each do |arg|
  case arg
  when "--with-wasmer" then with_wasmer = true
  when "--with-wasm32" then with_wasm32 = true
  else
    STDERR.puts "unknown option: #{arg}"
    exit 2
  end
end

step "shards install"
silent = Process.run("shards", ["install", "--without-development"],
  output: Process::Redirect::Close, error: Process::Redirect::Close)
run!("shards", ["install"]) unless silent.success?

step "bootstrap build"
run!("shards", ["build"])

step "build-docs (before the final build, so the binary embeds them)"
run!("bin/crystal-robots", ["build-docs"])

step "check manifest.uuid"

# Without it the shipped binary reports "unknown" for --version and
# /version, which defeats comparing a deploy against a specific
# check-in, so the release build (this one) refuses to ship that way;
# `crystal build`/`shards build` run by hand outside this script still
# fall back to "unknown", which is fine for local dev. A plain git
# clone (a mirror with no Fossil checkout behind it) never has
# manifest.uuid either, since it is a Fossil checkout artifact, not a
# versioned file (.fossil-settings/ignore-glob); fall back to the git
# commit HEAD is on there instead of failing outright.
def manifest_uuid_present? : Bool
  File.exists?("manifest.uuid") && File.size("manifest.uuid") > 0
end

if !manifest_uuid_present? && Dir.exists?(".git")
  head = IO::Memory.new
  status = Process.run("git", ["rev-parse", "HEAD"], output: head)
  File.write("manifest.uuid", head.to_s) if status.success?
end
unless manifest_uuid_present?
  STDERR.puts "manifest.uuid is missing or empty; run 'fossil setting manifest on' and check out from Fossil so the release build carries a check-in"
  exit 1
end

step "shards build"
run!("shards", ["build"])

spec_flags = [] of String

if with_wasmer
  step "wasmer 4.4.0"
  wasmer_dir = File.join(Dir.current, ".wasmer")
  # Exported for the rest of this process, not just the installer
  # below: the wasmer-crystal shard itself reads WASMER_DIR at
  # `crystal spec -Dwasmer` link time, later in this same run.
  ENV["WASMER_DIR"] = wasmer_dir
  wasmer_bin = File.join(wasmer_dir, "bin", "wasmer")
  wasmer_lib = File.join(wasmer_dir, "lib", "libwasmer.a")
  unless File::Info.executable?(wasmer_bin) && File.exists?(wasmer_lib)
    # Every write stays inside the checkout: the installer appends its
    # shell snippet to $PROFILE (when that file exists), downloads
    # through mktemp -t (honours $TMPDIR), and prompts if a stale
    # bin/wasmer is found, so a partial install is cleared first.
    rm_rf(wasmer_dir)
    Dir.mkdir_p(File.join(wasmer_dir, "tmp"))
    File.write(File.join(wasmer_dir, "profile.sh"), "")
    env = {
      "PROFILE"            => File.join(wasmer_dir, "profile.sh"),
      "TMPDIR"             => File.join(wasmer_dir, "tmp"),
      "WASMER_INSTALL_LOG" => "quiet",
    }
    run!("sh", ["scripts/install_wasmer.sh", "v4.4.0"], env: env)
    rm_rf(File.join(wasmer_dir, "tmp"))
  end
  ENV["PATH"] = "#{File.join(wasmer_dir, "bin")}:#{ENV["PATH"]?}"
  run!(File.join(wasmer_dir, "bin", "wasmer"), ["--version"])
  spec_flags << "-Dwasmer"
end

if with_wasm32
  step "check for node (drives the wasm32 specs through site/wasi-shim.js)"
  unless Process.find_executable("node")
    STDERR.puts "node is required on PATH for --with-wasm32"
    exit 1
  end
  run!("node", ["--version"])

  step "check for wasm-ld (the lld package; Crystal needs it to link the wasm32 target)"
  unless Process.find_executable("wasm-ld")
    STDERR.puts "wasm-ld is required on PATH for --with-wasm32; install the lld package"
    exit 1
  end

  step "wasm32-wasi-libs 0.0.3"
  wasm32_libs = File.join(Dir.current, ".wasm32-wasi-libs")
  libc = File.join(wasm32_libs, "lib", "wasm32-wasi", "libc.a")
  unless File.exists?(libc)
    rm_rf(wasm32_libs)
    run!("sh", ["scripts/install_wasm32_wasi_libs.sh", "0.0.3"])
  end

  step "build site/crystal-robots.wasm (the browser compiler)"
  Dir.mkdir_p("site")
  run!("crystal", ["build", "--target", "wasm32-unknown-wasi", "src/browser.cr", "-o", "site/crystal-robots.wasm",
                   "--link-flags=-L#{File.join(wasm32_libs, "lib", "wasm32-wasi")}", "--release", "--no-debug"])
  puts "#{File.info("site/crystal-robots.wasm").size} bytes: site/crystal-robots.wasm"

  spec_flags << "-Dcrd_wasm32"
end

step "crystal spec #{spec_flags.join(' ')}"
run!("crystal", ["spec"] + spec_flags)

step "crystal tool format --check"
run!("crystal", ["tool", "format", "--check", "src", "spec", "ci.cr"])

step "CLI smoke"
run!("bin/crystal-robots", ["-v"], output: Process::Redirect::Close)
run!("bin/crystal-robots", ["-t", "examples/hello.cr"], output: Process::Redirect::Close)
run!("bin/crystal-robots", ["-c", "examples/hello.cr", "-o", "bin/smoke.wasm"])
run!("bin/crystal-robots", ["-m", "1", "-l", "3000", "examples/counter.cr", "examples/target.cr"], output: Process::Redirect::Close)

suffix = String.build do |s|
  s << " (with wasmer)" if with_wasmer
  s << " (with wasm32)" if with_wasm32
end
puts "\n== ci.cr: all green#{suffix}"
