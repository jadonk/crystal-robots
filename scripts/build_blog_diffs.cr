# Build the small, annotated changes shown in the blog. Run in a git checkout.
require "yaml"
require "json"
require "option_parser"
require "html"

record DiffLine, kind : String, text : String, old : Int32?, new : Int32?

ref = "origin/main"
map_file = nil.as(String?)
overrides = {} of String => String
OptionParser.parse do |parser|
  parser.on("--source SUBJECT=SHA", "Use SHA for one exact subject") do |value|
    parts = value.split('=', 2)
    abort "--source needs SUBJECT=SHA" unless parts.size == 2
    overrides[parts[0]] = parts[1]
  end
  parser.on("--map FILE", "Read SUBJECT=SHA lines") { |value| map_file = value }
  parser.unknown_args do |args|
    abort "expected at most one REF" if args.size > 1
    ref = args[0] if args[0]?
  end
end
if file = map_file
  File.each_line(file) do |line|
    next if line.strip.empty? || line.starts_with?('#')
    parts = line.strip.split('=', 2)
    abort "#{file}: expected SUBJECT=SHA: #{line}" unless parts.size == 2
    overrides[parts[0]] = parts[1]
  end
end

# The Fossil CGI (src/web/ and spec/web/, apart from the robot API reference
# the public site's cheat sheet is built from) stays out of the public story.
def private_source?(path : String) : Bool
  return false if path.ends_with?("robot_api.cr") || path.ends_with?("robot_api_spec.cr")
  path.starts_with?("src/web/") || path.starts_with?("spec/web/") || path.includes?("fossil/cgi")
end

def git(*args : String) : String
  git_output = IO::Memory.new
  err = IO::Memory.new
  status = Process.run("git", args.to_a, output: git_output, error: err)
  abort "git #{args.join(" ")} failed: #{err}" unless status.success?
  git_output.to_s
end

sha_for = {} of String => String
git("log", "--format=%H%x09%s", ref).each_line do |line|
  sha, subject = line.split('\t', 2)
  sha_for[subject] ||= sha
end
notes = YAML.parse(File.read("site/blog/diffs/notes.yml"))
roles = notes["roles"].as_h
entries = notes["commits"].as_h
html = File.read("site/blog/index.html")
entries.each do |id_any, entry_any|
  id = id_any.to_s
  entry = entry_any
  section = html.match(Regex.new(%(<section class="commit[^"]*" id="#{Regex.escape(id)}">(.*?)</section>), Regex::Options::MULTILINE))
  abort "#{id}: section missing" unless section
  if note = entry["note"]?
    abort "#{id}: a summary-only view cannot have excerpts" unless entry["excerpts"].as_a.empty?
    output = JSON.build do |json|
      json.object do
        json.field "summary", entry["summary"].to_s
        json.field "note", note.to_s
        json.field "files", [] of String
        json.field "excerpts", [] of String
      end
    end
    File.write("site/blog/diffs/#{id}.json", JSON.parse(output).to_pretty_json + "\n")
    puts "#{id}: summary only"
    next
  end
  subject_match = section[1].match(/data-subject="([^"]+)"/)
  abort "#{id}: subject missing" unless subject_match
  subject = HTML.unescape(subject_match[1])
  mapped_sha = overrides[subject]?
  sha = mapped_sha || sha_for[subject]? || abort "#{id}: subject not on #{ref}: #{subject} (use --source or --map)"
  actual = git("show", "-s", "--format=%s", sha).strip
  abort "#{id}: #{sha} has subject #{actual.inspect}, expected #{subject.inspect}" unless mapped_sha || actual == subject
  parent = git("rev-list", "--parents", "-n", "1", sha).split[1]? || git("hash-object", "-t", "tree", "--stdin").strip
  files = [] of NamedTuple(path: String, added: Int32, removed: Int32, role: String)
  git("diff", "--numstat", parent, sha).each_line do |line|
    added, removed, path = line.rstrip.split('\t', 3)
    next if {"manifest.uuid", "shard.lock"}.includes?(path) || private_source?(path)
    role = roles[path]?.try(&.to_s) || roles.find { |prefix, _| path.starts_with?(prefix.to_s) }.try(&.[1].to_s) || "Project file."
    files << {path: path, added: added.to_i? || 0, removed: removed.to_i? || 0, role: role}
  end
  excerpts = [] of NamedTuple(file: String, note: String, lines: Array(DiffLine), before: Array(DiffLine), after: Array(DiffLine), line_notes: Hash(String, String))
  entry["excerpts"].as_a.each do |ex|
    path = ex["file"].to_s
    abort "#{id}: private source #{path}" if private_source?(path)
    anchor = ex["anchor"].to_s
    diff = git("diff", "--unified=12", parent, sha, "--", path)
    hunks = [] of Array(DiffLine)
    current = nil.as(Array(DiffLine)?)
    old_no = 0
    new_no = 0
    diff.each_line do |raw|
      line = raw.rstrip('\n')
      if m = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/)
        old_no = m[1].to_i
        new_no = m[2].to_i
        current = [] of DiffLine
        hunks << current
      elsif hunk = current
        next if line.starts_with?("\\ No newline")
        case line[0]?
        when '+'
          hunk << DiffLine.new("+", line[1..], nil, new_no)
          new_no += 1
        when '-'
          hunk << DiffLine.new("-", line[1..], old_no, nil)
          old_no += 1
        when ' '
          hunk << DiffLine.new(" ", line[1..], old_no, new_no)
          old_no += 1
          new_no += 1
        end
      end
    end
    matches = [] of {Array(DiffLine), Int32}
    hunks.each do |hunk|
      hunk.each_with_index { |line, index| matches << {hunk, index} if line.text.includes?(anchor) }
    end
    abort "#{id}: anchor #{anchor.inspect} in #{path} matched #{matches.size} lines (need exactly one)" unless matches.size == 1
    hunk, index = matches.first
    if through = ex["through"]?
      end_matches = [] of {Array(DiffLine), Int32}
      hunks.each do |candidate|
        candidate.each_with_index { |line, position| end_matches << {candidate, position} if line.text.includes?(through.to_s) }
      end
      abort "#{id}: through #{through} in #{path} matched #{end_matches.size} lines (need exactly one)" unless end_matches.size == 1
      abort "#{id}: through #{through} is outside the anchor's hunk in #{path}" unless end_matches.first[0] == hunk
      abort "#{id}: through #{through} comes before anchor #{anchor} in #{path}" if end_matches.first[1] < index
      first = index
      last = end_matches.first[1] + 1
    else
      before_count = ex["before"]?.try(&.as_i) || 3
      after_count = ex["after"]?.try(&.as_i) || 4
      first = Math.max(0, index - before_count)
      last = Math.min(hunk.size, index + after_count + 1)
    end
    core = hunk[first...last]
    abort "#{id}: excerpt has no added line: #{path}" unless core.any? { |line| line.kind == "+" }
    context_before = Math.min(12, ex["context_before"]?.try(&.as_i) || 12)
    more_before = hunk[Math.max(0, first - context_before)...first]
    more_after = hunk[last...Math.min(hunk.size, last + 12)]
    line_notes = {} of String => String
    if specified = ex["line_notes"]?
      specified.as_h.each do |key, value|
        count = core.count { |line| line.text.includes?(key.to_s) }
        abort "#{id}: line note #{key} matched #{count} lines" unless count == 1
        line_notes[key.to_s] = value.to_s
      end
    end
    excerpts << {file: path, note: ex["note"].to_s, lines: core, before: more_before, after: more_after, line_notes: line_notes}
  end
  output = JSON.build do |json|
    json.object do
      json.field "sha", sha
      json.field "subject", subject
      json.field "summary", entry["summary"].to_s
      json.field "files" do
        json.array do
          files.each do |file|
            json.object do
              json.field "path", file[:path]
              json.field "added", file[:added]
              json.field "removed", file[:removed]
              json.field "role", file[:role]
            end
          end
        end
      end
      json.field "excerpts" do
        json.array do
          excerpts.each do |excerpt|
            json.object do
              json.field "file", excerpt[:file]
              json.field "note", excerpt[:note]
              {"before" => excerpt[:before], "lines" => excerpt[:lines], "after" => excerpt[:after]}.each do |key, lines|
                json.field key do
                  json.array do
                    lines.each do |line|
                      json.object do
                        json.field "kind", line.kind
                        json.field "text", line.text
                        json.field "old", line.old
                        json.field "new", line.new
                      end
                    end
                  end
                end
              end
              json.field "line_notes", excerpt[:line_notes]
            end
          end
        end
      end
    end
  end
  File.write("site/blog/diffs/#{id}.json", JSON.parse(output).to_pretty_json + "\n")
  puts "#{id}: #{sha[0, 7]}"
end
