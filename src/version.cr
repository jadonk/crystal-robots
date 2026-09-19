module CrystalRobots
  VERSION = "0.0.1"

  # The Fossil check-in this binary was built from. Fossil's versioned
  # `manifest` setting (.fossil-settings/manifest holds "u") keeps
  # `manifest.uuid` in every checkout and tarball; it is read once, at
  # compile time. "unknown" when built from a plain source tree with
  # neither a checkout's generated file nor one written some other way.
  CHECKIN = {{ (read_file?("#{__DIR__}/../manifest.uuid") || "unknown").strip }}

  # Short check-in for display, like Fossil's own timeline.
  def self.checkin_short : String
    CHECKIN == "unknown" ? CHECKIN : CHECKIN[0, 10]
  end

  # "0.0.1 (check-in 724ff90d58)": what --version and /version report, so
  # a deploy can be compared against a specific check-in.
  def self.version_line : String
    "crystal-robots #{VERSION} (check-in #{checkin_short})"
  end
end
