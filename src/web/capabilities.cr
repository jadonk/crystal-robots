# The capability gate, modeled on the tiers GP-Crystal and Ollama-Codex
# already use for a Fossil-served app: identity is `FOSSIL_USER`,
# permission is `FOSSIL_CAPABILITIES`, both supplied by Fossil itself
# (this app never handles credentials). Shorthand letters expand the
# same way Fossil's own login capabilities do: `s` (setup) and `a`
# (admin) imply every capability; `v` (developer) expands to `eoih`; `u`
# (reader) expands to `oh`. Routes then require a specific letter: `o` or
# `h` to read the overview and examples, `i` to run the checker, the
# interpreter or a battle, `j` to read a saved robot's wiki page.
module CrystalRobots::Web::Capabilities
  def self.expand(raw : String) : Set(Char)
    caps = raw.chars.to_set
    return ('a'..'z').to_set if caps.includes?('s') || caps.includes?('a')
    caps.concat("eoih".chars) if caps.includes?('v')
    caps.concat("oh".chars) if caps.includes?('u')
    caps
  end

  def self.can_read?(raw : String) : Bool
    caps = expand(raw)
    caps.includes?('o') || caps.includes?('h')
  end

  # Parsing, checking, interpreting and running a battle.
  def self.can_run?(raw : String) : Bool
    expand(raw).includes?('i')
  end

  # Reading a saved robot's wiki page.
  def self.can_read_wiki?(raw : String) : Bool
    expand(raw).includes?('j')
  end
end
