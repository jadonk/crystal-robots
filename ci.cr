# The daemon's automatic gate runs this file after every finished task; it
# only forwards to scripts/ci.sh so that script stays the one CI command.
status = Process.run("sh", ["scripts/ci.sh"] + ARGV,
  chdir: __DIR__, output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
exit(status.exit_code)
