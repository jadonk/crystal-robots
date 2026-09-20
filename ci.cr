# ci.cr — the one CI command: everything the task pipeline, trunk-ops and a
# developer run before trusting a revision. Exits non-zero on any failure.
#
#   crystal run ci.cr --                 # build docs, build, spec, format, examples
#   crystal run ci.cr -- --with-wasmer   # also run the WebAssembly specs under wasmer 4.4.0,
#                                         # installing it under ./.wasmer when absent
#   crystal run ci.cr -- --with-wasm32   # also build site/crystal-robots.wasm (Phase 5b-1,
#                                         # the browser compiler) and run its specs; installs
#                                         # wasm32-wasi-libs under ./.wasm32-wasi-libs; needs
#                                         # `node` on PATH (its specs drive the module through
#                                         # site/wasi-shim.js, the same code the browser loads)
#
# Without --with-wasmer the wasmer specs are reported as pending with their
# reason, and without --with-wasm32 the wasm32 specs are too; neither is
# ever a tolerated failure.
#
# Porting decision on wasmer: scripts/install_wasmer.sh is a 13 KB upstream
# installer doing platform/arch detection, checksum verification and
# several download fallbacks, for a dependency only pulled in by the opt-in
# --with-wasmer flag. Reimplementing all of that in Crystal is out of
# proportion to what it buys, so ci.cr keeps calling that pinned installer
# script directly (still the one non-Crystal step left) rather than porting
# it. wasm32-wasi-libs, by contrast, is a plain tarball fetch with no
# platform logic, so it is ported below as ordinary Crystal using
# HTTP::Client.
require "http/client"
require "file_utils"

CHECKOUT = __DIR__

def announce(name : String) : Nil
  puts
  puts "== #{name}"
end

def fail!(name : String, status : Process::Status) : NoReturn
  STDERR.puts "ci.cr: step failed: #{name} (exit #{status.exit_code})"
  exit(status.exit_code == 0 ? 1 : status.exit_code)
end

def exec!(name : String, command : String, args : Array(String) = [] of String,
          chdir : String = CHECKOUT, env : Process::Env = nil) : Nil
  status = Process.run(command, args, chdir: chdir, env: env,
    output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
  fail!(name, status) unless status.success?
end

def step!(name : String, command : String, args : Array(String) = [] of String,
          chdir : String = CHECKOUT, env : Process::Env = nil) : Nil
  announce(name)
  exec!(name, command, args, chdir, env)
end

# Follows redirects itself: GitHub release assets 302 to a signed
# release-assets.githubusercontent.com URL.
def download(url : String, dest : String) : Nil
  current = url
  6.times do
    uri = URI.parse(current)
    client = HTTP::Client.new(uri)
    redirect_to = nil
    begin
      client.get(uri.request_target) do |response|
        if response.status.redirection?
          location = response.headers["Location"]? || raise "redirect from #{current} has no Location header"
          redirect_to = uri.resolve(location).to_s
        elsif response.status.success?
          File.open(dest, "w") do |file|
            IO.copy(response.body_io, file)
          end
        else
          raise "GET #{current} failed: HTTP #{response.status_code}"
        end
      end
    ensure
      client.close
    end
    return if redirect_to.nil?
    current = redirect_to.not_nil!
  end
  raise "too many redirects fetching #{url}"
end

# Ported from scripts/install_wasm32_wasi_libs.sh: downloads the pinned
# wasm-libs release (https://github.com/lbguilherme/wasm-libs), verifies
# the extraction produced the expected layout, and installs lib/ and
# include/ under `dest`. Pinned so a new upstream release cannot change
# what CI links against silently.
def install_wasm32_wasi_libs(version : String, dest : String) : Nil
  asset = "wasm32-wasi-sysroot.tar.gz"
  url = "https://github.com/lbguilherme/wasm-libs/releases/download/#{version}/#{asset}"
  puts "Installing wasm32-wasi-libs #{version} into #{dest}"
  FileUtils.mkdir_p(dest)
  tmp_dir = File.tempname("wasm32-wasi-libs")
  FileUtils.mkdir_p(tmp_dir)
  begin
    archive = File.join(tmp_dir, asset)
    download(url, archive)
    extracted = File.join(tmp_dir, "wasm32-wasi-sysroot")
    status = Process.run("tar", ["-xzf", archive, "-C", tmp_dir])
    raise "failed to extract #{archive}" unless status.success?
    raise "#{extracted} missing lib/ or include/ after extraction" unless Dir.exists?(File.join(extracted, "lib")) && Dir.exists?(File.join(extracted, "include"))
    FileUtils.rm_rf(File.join(dest, "lib"))
    FileUtils.rm_rf(File.join(dest, "include"))
    FileUtils.mv(File.join(extracted, "lib"), File.join(dest, "lib"))
    FileUtils.mv(File.join(extracted, "include"), File.join(dest, "include"))
  ensure
    FileUtils.rm_rf(tmp_dir)
  end
  puts "wasm32-wasi-libs #{version} installed: #{File.join(dest, "lib", "wasm32-wasi")}"
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

announce("shards install")
quiet = Process.run("shards", ["install", "--without-development"], chdir: CHECKOUT,
  output: Process::Redirect::Close, error: Process::Redirect::Close)
unless quiet.success?
  exec!("shards install", "shards", ["install"])
end

step!("bootstrap build", "shards", ["build"])

step!("build-docs (before the final build, so the binary embeds them)",
  "bin/crystal-robots", ["build-docs"])

announce("check manifest.uuid")
# Without it the shipped binary reports "unknown" for --version and
# /version, which defeats comparing a deploy against trunk, so the release
# build (below) refuses to ship that way; `crystal build`/`shards build`
# run by hand outside ci.cr still fall back to "unknown", which is fine
# for local dev.
#
# A plain `git clone` (the GitHub mirror .github/workflows/pages.yml runs
# ci.cr from) never has manifest.uuid: it is a Fossil checkout artifact,
# not a versioned file (.fossil-settings/ignore-glob). The mirror's git
# history is exported straight from Fossil, one commit per check-in, so
# the git commit HEAD is on identifies the same revision manifest.uuid
# would; use it there instead of failing outright.
manifest_path = File.join(CHECKOUT, "manifest.uuid")
manifest_missing = -> { !File.exists?(manifest_path) || File.size(manifest_path) == 0 }
if manifest_missing.call && Dir.exists?(File.join(CHECKOUT, ".git"))
  head = IO::Memory.new
  status = Process.run("git", ["rev-parse", "HEAD"], chdir: CHECKOUT,
    output: head, error: Process::Redirect::Inherit)
  File.write(manifest_path, head.to_s.strip) if status.success? && !head.to_s.strip.empty?
end
if manifest_missing.call
  STDERR.puts "manifest.uuid is missing or empty; run 'fossil setting manifest on' and check out from Fossil so the release build carries a check-in"
  exit 1
end

step!("shards build", "shards", ["build"])

spec_flags = [] of String

if with_wasmer
  announce("wasmer 4.4.0")
  wasmer_dir = File.join(CHECKOUT, ".wasmer")
  wasmer_bin = File.join(wasmer_dir, "bin", "wasmer")
  wasmer_lib = File.join(wasmer_dir, "lib", "libwasmer.a")
  unless File::Info.executable?(wasmer_bin) && File.exists?(wasmer_lib)
    # Every write stays inside the checkout: the installer appends its
    # shell snippet to $PROFILE (when that file exists), downloads through
    # mktemp -t (honours $TMPDIR), and prompts if a stale bin/wasmer is
    # found, so a partial install is cleared first.
    FileUtils.rm_rf(wasmer_dir)
    tmp_dir = File.join(wasmer_dir, "tmp")
    FileUtils.mkdir_p(tmp_dir)
    File.write(File.join(wasmer_dir, "profile.sh"), "")
    install_env = {
      "PROFILE"            => File.join(wasmer_dir, "profile.sh"),
      "TMPDIR"             => tmp_dir,
      "WASMER_INSTALL_LOG" => "quiet",
      "WASMER_DIR"         => wasmer_dir,
    }
    exec!("wasmer 4.4.0", "sh", ["scripts/install_wasmer.sh", "v4.4.0"], env: install_env)
    FileUtils.rm_rf(tmp_dir)
  end
  ENV["PATH"] = "#{File.join(wasmer_dir, "bin")}:#{ENV["PATH"]}"
  exec!("wasmer --version", wasmer_bin, ["--version"])
  spec_flags << "-Dwasmer"
end

if with_wasm32
  announce("check for node (drives the wasm32 specs through site/wasi-shim.js)")
  node = Process.find_executable("node")
  if node.nil?
    STDERR.puts "node is required on PATH for --with-wasm32"
    exit 1
  end
  exec!("node --version", node, ["--version"])

  announce("check for wasm-ld (the lld package; Crystal needs it to link the wasm32 target)")
  if Process.find_executable("wasm-ld").nil?
    STDERR.puts "wasm-ld is required on PATH for --with-wasm32; install the lld package"
    exit 1
  end

  announce("wasm32-wasi-libs 0.0.3")
  wasm32_libs = File.join(CHECKOUT, ".wasm32-wasi-libs")
  unless File.exists?(File.join(wasm32_libs, "lib", "wasm32-wasi", "libc.a"))
    FileUtils.rm_rf(wasm32_libs)
    install_wasm32_wasi_libs("0.0.3", wasm32_libs)
  end

  announce("build site/crystal-robots.wasm (the browser compiler, Phase 5b-1)")
  FileUtils.mkdir_p(File.join(CHECKOUT, "site"))
  exec!("build site/crystal-robots.wasm", "crystal", [
    "build", "--target", "wasm32-unknown-wasi", "src/browser.cr",
    "-o", "site/crystal-robots.wasm",
    "--link-flags=-L#{File.join(wasm32_libs, "lib", "wasm32-wasi")}",
    "--release", "--no-debug",
  ])
  wasm_size = File.size(File.join(CHECKOUT, "site", "crystal-robots.wasm"))
  puts "site/crystal-robots.wasm: #{wasm_size} bytes"

  spec_flags << "-Dcrd_wasm32"
end

step!("crystal spec #{spec_flags.join(" ")}", "crystal", ["spec"] + spec_flags)

step!("crystal tool format --check", "crystal", ["tool", "format", "--check", "src", "spec", "scripts"])

announce("example robots build natively with the prelude")
FileUtils.mkdir_p(File.join(CHECKOUT, "bin"))
Dir.glob(File.join(CHECKOUT, "examples", "*.cr")).sort.each do |robot|
  name = File.basename(robot, ".cr")
  exec!("example #{name}", "crystal",
    ["build", "--prelude=../src/prelude", "#{name}.cr", "-o", "../bin/example-#{name}"],
    chdir: File.join(CHECKOUT, "examples"))
end

announce("CLI smoke")
cli = File.join(CHECKOUT, "bin", "crystal-robots")

def smoke!(cli : String, args : Array(String), discard_output : Bool) : Nil
  status = Process.run(cli, args, chdir: CHECKOUT,
    output: discard_output ? Process::Redirect::Close : Process::Redirect::Inherit,
    error: Process::Redirect::Inherit)
  fail!("CLI smoke: #{args.join(" ")}", status) unless status.success?
end

smoke!(cli, ["-v"], true)
smoke!(cli, ["-t", "examples/test.cr"], true)
smoke!(cli, ["-c", "examples/test.cr", "-o", "bin/test.wasm"], false)
smoke!(cli, ["-m", "1", "-l", "3000", "examples/counter.cr", "examples/target.cr"], true)

suffix = String.build do |s|
  s << " (with wasmer)" if with_wasmer
  s << " (with wasm32)" if with_wasm32
end
puts
puts "== ci.cr: all green#{suffix}"
