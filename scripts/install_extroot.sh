#!/bin/sh
# Install the Crystal Robots CGI into a Fossil extension root.
#
#   scripts/install_extroot.sh /path/to/extroot
#
# Creates the symlink <extroot>/robots -> <checkout>/bin/crystal-robots, so
# `fossil server --extroot /path/to/extroot` serves the app at /ext/robots
# and a rebuild (`shards build`) is the deploy.
set -e
extroot="$1"
if [ -z "$extroot" ]; then
  echo "usage: $0 EXTROOT" >&2
  exit 2
fi
here="$(cd "$(dirname "$0")/.." && pwd)"
bin="$here/bin/crystal-robots"
if [ ! -x "$bin" ]; then
  echo "$bin is not built; run 'shards build' first" >&2
  exit 1
fi
mkdir -p "$extroot"
ln -sfn "$bin" "$extroot/robots"
echo "$extroot/robots -> $bin"
