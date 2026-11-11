# Copied unchanged from ocx-console (MIT, https://ollama.openbeagle.org/ocx-console),
# check-in 170ebb1105, tools/browser-rootfs/rootfs.cr. crystal-robots uses it for
# make-static, the Alpine static libraries ci.cr's release build links
# (patterns/stage.md), and, with make, for a headless Chromium.
#
# browser_rootfs: an Alpine root file system holding a headless browser, made
# and entered without root, so this session can open the console's pages.
#
# The seed is bootstrap-qcow2's (github.com/embedconsult/bootstrap-qcow2,
# src/sysroot_builder.cr and src/alpine_setup.cr): Alpine's minirootfs, checked
# against Alpine's own .sha256, then etc/resolv.conf written from outside, then
# packages added with apk from inside. Inside is entered with bwrap in a user
# namespace, as root mapped to this user, where bootstrap-qcow2 uses its own
# unshare and pivot_root.
#
#   crystal run tools/browser-rootfs/browser_rootfs.cr -- make [ROOTFS]
#   crystal run tools/browser-rootfs/browser_rootfs.cr -- run ROOTFS -- COMMAND...
#
# ROOTFS defaults to $HOME/browser-rootfs. `make` is safe to run again: it
# downloads and extracts only once, and apk adds only what is missing.

require "digest/sha256"
require "file_utils"
require "http/client"

module BrowserRootfs
  ALPINE_BRANCH  = "v3.23"
  ALPINE_VERSION = "3.23.2"
  ARCH           = "x86_64"
  NAMESERVER     = "8.8.8.8"
  # Chromium, and the static libraries the console's static build links
  # (README.md, "Build").
  STATIC   = %w[sqlite-static gc-static pcre2-static zlib-static libunwind-static xz-static]
  PACKAGES = %w[chromium font-dejavu] + STATIC

  def self.minirootfs_url : String
    file = "alpine-minirootfs-#{ALPINE_VERSION}-#{ARCH}.tar.gz"
    "https://dl-cdn.alpinelinux.org/alpine/#{ALPINE_BRANCH}/releases/#{ARCH}/#{file}"
  end

  # A URL's body, following up to five redirects (GitHub's downloads redirect).
  def self.fetch(url : String, redirects = 5) : Bytes
    HTTP::Client.get(url) do |response|
      if response.status.redirection? && redirects > 0 && (to = response.headers["Location"]?)
        return fetch(URI.parse(url).resolve(to).to_s, redirects - 1)
      end
      raise "#{url}: HTTP #{response.status_code}" unless response.success?
      io = IO::Memory.new
      IO.copy(response.body_io, io)
      io.to_slice
    end
  end

  # Downloads the minirootfs beside ROOTFS, checks its SHA-256 against
  # Alpine's, and extracts it into ROOTFS.
  def self.seed(rootfs : Path) : Nil
    if File.exists?(rootfs / "etc/alpine-release")
      puts "seed: #{rootfs} already holds Alpine #{File.read(rootfs / "etc/alpine-release").strip}"
      return
    end
    url = minirootfs_url
    expected = String.new(fetch(url + ".sha256")).split.first
    tarball = rootfs.parent / File.basename(url)
    unless File.exists?(tarball) && Digest::SHA256.hexdigest(File.read(tarball).to_slice) == expected
      File.write(tarball, fetch(url))
    end
    actual = Digest::SHA256.hexdigest(File.read(tarball).to_slice)
    raise "#{tarball}: sha256 #{actual}, Alpine says #{expected}" unless actual == expected
    puts "seed: #{File.basename(url)} sha256 #{actual}, as Alpine's"
    FileUtils.mkdir_p(rootfs)
    run!(["tar", "-xzf", tarball.to_s, "-C", rootfs.to_s])
  end

  # As bootstrap-qcow2's AlpineSetup.write_resolv_conf: DNS is written from
  # outside, before entering.
  def self.write_resolv_conf(rootfs : Path) : Nil
    File.write(rootfs / "etc/resolv.conf", "nameserver #{NAMESERVER}\n")
  end

  # The bwrap command entering ROOTFS as root of a new user namespace, with the
  # host's network, a fresh /proc, /dev and /tmp, and /dev/shm for Chromium.
  def self.enter(rootfs : Path, command : Array(String)) : Array(String)
    ["bwrap",
     "--unshare-user", "--uid", "0", "--gid", "0",
     "--bind", rootfs.to_s, "/",
     "--proc", "/proc", "--dev", "/dev",
     "--tmpfs", "/tmp", "--tmpfs", "/dev/shm",
     "--setenv", "HOME", "/root",
     "--setenv", "PATH", "/usr/sbin:/usr/bin:/sbin:/bin",
     "--chdir", "/",
     "--"] + command
  end

  def self.run!(argv : Array(String)) : Nil
    status = Process.run(argv[0], argv[1..], output: STDOUT, error: STDERR)
    raise "#{argv.first(3).join(" ")}… exited #{status.exit_code}" unless status.success?
  end

  # Only the static libraries, for a stage run's build (patterns/stage.md):
  # Chromium is bigger than a stage run may write.
  def self.make(rootfs : Path, static_only = false) : Nil
    seed(rootfs)
    write_resolv_conf(rootfs)
    run!(enter(rootfs, ["apk", "add", "--no-cache"] + (static_only ? STATIC : PACKAGES)))
    run!(enter(rootfs, ["chromium-browser", "--version"])) unless static_only
  end

  def self.main(args : Array(String)) : Int32
    default = Path[ENV["HOME"]] / "browser-rootfs"
    case args.first?
    when "make"
      make(args[1]? ? Path[args[1]].expand : default)
    when "make-static"
      make(args[1]? ? Path[args[1]].expand : default, static_only: true)
    when "run"
      split = args.index("--") || abort("usage: run ROOTFS -- COMMAND...")
      rootfs = split > 1 ? Path[args[1]].expand : default
      argv = enter(rootfs, args[(split + 1)..])
      return Process.run(argv[0], argv[1..], input: STDIN, output: STDOUT, error: STDERR).exit_code
    else
      abort("usage: browser_rootfs make [ROOTFS] | make-static [ROOTFS] | run [ROOTFS] -- COMMAND...")
    end
    0
  end
end
