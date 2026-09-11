# API documentation, built by `bin/crystal-robots build-docs` (which runs
# `crystal docs` into `docs-api/`, an ignored directory) and embedded into
# the binary at compile time, the way Ollama-Codex embeds its own docs.
#
# The generated pages are not served as they are: their own UI needs an
# inline script that Fossil's content security policy blocks. Instead each
# page's body is extracted, its scripts and search box dropped, its type
# index kept as plain links, and the result wrapped in Fossil's
# `fossil-doc` div so the repository skin frames it, the same approach as
# Ollama-Codex's docs CGI. The doc-comment content is untouched.
#
# `build-docs` must run before the final `shards build`, or the binary
# ships without docs and the route says so.
module CrystalRobots::Web
  module Docs
    DIR = "docs-api"

    # path relative to DIR => file content, captured when the binary was
    # built. search-index.js and index.json are left out: they only back
    # crystal-docs' own search box, which the page transform below drops.
    FILES = {% begin %}
      {
        {% root = "#{__DIR__}/../../docs-api" %}
        {% files = `find #{root} -type f -not -name search-index.js -not -name index.json 2>/dev/null || true`.split %}
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
      ".json" => "application/json",
      ".svg"  => "image/svg+xml",
      ".png"  => "image/png",
      ".txt"  => "text/plain; charset=utf-8",
    }

    # Styles for the extracted content, inline because Fossil's policy allows
    # inline styles and forbids scripts. Scoped under .crystal-docs.
    STYLE = <<-CSS
      <style>
      .crystal-docs .types-list { font-size: 90%; margin-bottom: 1.5em }
      .crystal-docs .types-list ul { list-style: none; padding-left: 1em; margin: 0 }
      .crystal-docs .types-list li { margin: 0.1em 0 }
      .crystal-docs .main-content h1.type-name { font-size: 1.6em }
      .crystal-docs .superclass-hierarchy { list-style: none; padding: 0 }
      .crystal-docs .superclass-hierarchy li { display: inline }
      .crystal-docs .superclass-hierarchy li:not(:first-child):before { content: " < " }
      .crystal-docs .list-summary { list-style: none; padding-left: 0 }
      .crystal-docs .entry-summary { margin: 0.25em 0 }
      .crystal-docs .entry-detail { border-top: 1px solid #ccc; padding-top: 0.5em; margin-top: 1em }
      .crystal-docs .signature { font-family: monospace }
      .crystal-docs .anchor { text-decoration: none; margin-right: 0.3em }
      .crystal-docs .octicon-link { display: none }
      .crystal-docs pre { padding: 0.5em; overflow-x: auto; background: rgba(127,127,127,0.12) }
      .crystal-docs .search-box, .crystal-docs .search-results, .crystal-docs .sidebar-header { display: none }
      </style>
      CSS

    # True when the binary carries a built documentation set.
    def self.built? : Bool
      FILES.has_key?("index.html")
    end

    def self.mime(path : String) : String
      MIME[File.extname(path)]? || "application/octet-stream"
    end

    # A raw (non-HTML) asset, or nil. Stylesheets and scripts are never
    # served: the page transform replaces them.
    def self.asset(path : String) : String?
      return nil if path.includes?("..") || path.ends_with?(".css") || path.ends_with?(".js")
      FILES[path]?
    end

    # A generated page transformed for the Fossil chrome, or nil. Returns the
    # page title and the HTML fragment for a `fossil-doc` wrapper.
    def self.page(path : String) : {String, String}?
      return nil if path.includes?("..") || !path.ends_with?(".html")
      html = FILES[path]?
      return nil unless html
      title = html[/<title>(.*?)<\/title>/m, 1]? || "API"
      title = title.split(" - ")[0]
      body = html[/<body[^>]*>(.*)<\/body>/m, 1]? || html
      body = body.gsub(/<script.*?<\/script>/mi, "")
      body = body.gsub(/<input[^>]*>/i, "")
      body = body.gsub(/<link[^>]*>/i, "")
      # belt and braces: the generator is trusted, but strip anything that
      # would still run script if that ever changed.
      body = body.gsub(/\s+on\w+\s*=\s*"[^"]*"/i, "")
      body = body.gsub(/\s+on\w+\s*=\s*'[^']*'/i, "")
      body = body.gsub(/(href|src)(\s*=\s*")javascript:[^"]*(")/i, "\\1\\2#\\3")
      body = body.gsub(/(href|src)(\s*=\s*')javascript:[^']*(')/i, "\\1\\2#\\3")
      # relative links inside the generated site keep working because the
      # page keeps its place in the tree; only absolute-root links would not
      {title, STYLE + "<div class=\"crystal-docs\">" + body + "</div>"}
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
