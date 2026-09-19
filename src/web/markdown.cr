# Small helpers for building the Markdown `Web::App` responds with.
# `fence` in particular exists for untrusted text (a pasted robot, an
# error message): a fence sized to one backtick longer than the longest
# run already in the text can never be closed early by the text itself.
module CrystalRobots::Web::Markdown
  def self.fence(text : String, lang : String = "") : String
    longest = text.scan(/`+/).map { |m| m[0].size }.max? || 0
    fence = "`" * Math.max(longest + 1, 3)
    "#{fence}#{lang}\n#{text}\n#{fence}\n"
  end

  # Escapes the handful of characters that would otherwise be read as
  # Markdown syntax, for untrusted text used outside a fence (an error
  # message quoting part of a robot's source, say).
  def self.escape(text : String) : String
    text.gsub(/[\\`*_\[\]()<>]/) { |c| "\\#{c}" }
  end
end
