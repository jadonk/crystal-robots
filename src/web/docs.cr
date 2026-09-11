# API documentation, built by `bin/crystal-robots build-docs` (which runs
# `crystal docs` into `docs-api/`, an ignored directory) and embedded into
# the binary at compile time, the way Ollama-Codex embeds its own docs.
# Served raw at `/ext/crystal-robots/docs/...`: the pages are a complete
# site with their own CSS and JavaScript, so they bypass the Fossil chrome.
#
# `build-docs` must run before the final `shards build`, or the binary
# ships without docs and the route says so.
module CrystalRobots::Web
  module Docs
    DIR = "docs-api"

    # path relative to DIR => file content, captured when the binary was built
    FILES = {% begin %}
      {
        {% root = "#{__DIR__}/../../docs-api" %}
        {% files = `find #{root} -type f 2>/dev/null || true`.split %}
        {% if files.empty? %}
          "" => "",
        {% else %}
          {% for file in files.sort %}
            {{ file[(root.size + 1)..] }} => {{ read_file(file) }},
          {% end %}
        {% end %}
      }
    {% end %}

    MIME = {
      ".html" => "text/html; charset=utf-8",
      ".css"  => "text/css",
      ".js"   => "text/javascript",
      ".json" => "application/json",
      ".svg"  => "image/svg+xml",
      ".png"  => "image/png",
      ".txt"  => "text/plain; charset=utf-8",
    }

    # True when the binary carries a built documentation set.
    def self.built? : Bool
      FILES.has_key?("index.html")
    end

    def self.mime(path : String) : String
      MIME[File.extname(path)]? || "application/octet-stream"
    end

    # The content for a docs path, or nil.
    def self.get(path : String) : String?
      return nil if path.includes?("..")
      FILES[path]?
    end

    # Run `crystal docs` for the prelude (the robot API) and the compiler,
    # into DIR. Called by the `build-docs` subcommand.
    def self.build(version : String) : Bool
      args = ["docs", "-o", DIR, "--project-name", "crystal-robots", "--project-version", version,
              "--canonical-base-url", "/ext/crystal-robots/docs/",
              "src/prelude.cr", "src/crystal-robots.cr"]
      status = Process.run("crystal", args, output: STDOUT, error: STDERR)
      status.success?
    end
  end
end
