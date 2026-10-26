# Re-points site/blog/index.html's commit links at a git branch's current
# SHAs. Every link carries data-subject="<exact commit subject>", so if the
# main line is ever re-committed (new SHAs, same subjects), run this from a
# git checkout and commit the result:
#
#   crystal run scripts/resolve_blog_links.cr -- [REF] [FILE]
#
# REF defaults to origin/main, FILE to site/blog/index.html. A subject the
# branch doesn't have is reported and its link left alone; the exit status
# is 1 if any were missing.
require "html"

ref = ARGV[0]? || "origin/main"
file = ARGV[1]? || "site/blog/index.html"

log = IO::Memory.new
status = Process.run("git", ["log", "--format=%H%x09%s", ref], output: log, error: STDERR)
abort "git log #{ref} failed" unless status.success?
sha_for = {} of String => String
log.to_s.each_line do |line|
  sha, subject = line.split('\t', 2)
  sha_for[subject] ||= sha
end

missing = [] of String
changed = 0
html = File.read(file).gsub(%r{href="(https://github\.com/[^"]+/commit/)([0-9a-f]{40})"( data-subject="([^"]*)")>([^<]*)</a>}) do
  prefix, old, attr, encoded, text = $1, $2, $3, $4, $5
  subject = HTML.unescape(encoded)
  if sha = sha_for[subject]?
    changed += 1 if sha != old
    # A link labelled with the old short hash gets the new one.
    label = old.starts_with?(text) && !text.empty? ? sha[0, text.size] : text
    %(href="#{prefix}#{sha}"#{attr}>#{label}</a>)
  else
    missing << subject
    $0
  end
end
File.write(file, html)
puts "#{file}: #{changed} link(s) updated from #{ref}"
missing.uniq.each { |subject| STDERR.puts "not on #{ref}: #{subject}" }
exit(missing.empty? ? 0 : 1)
