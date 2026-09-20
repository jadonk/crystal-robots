#!/bin/sh
# Publish robots/*.md as Fossil wiki pages named robot/<name>, creating or
# updating each page. Run on the host against the served repository:
#
#   scripts/publish_wiki_robots.sh -R /path/to/crystal-robots.fossil
#
# Without -R the repository of the current checkout is used.
set -e
repo=""
if [ "$1" = "-R" ]; then
  repo="$2"
fi
here="$(cd "$(dirname "$0")/.." && pwd)"
if [ -n "$repo" ]; then
  existing="$(fossil wiki list -R "$repo")"
else
  existing="$(fossil wiki list)"
fi
for file in "$here"/robots/*.md; do
  name="robot/$(basename "$file" .md)"
  if printf '%s\n' "$existing" | grep -qx "$name"; then
    verb=commit
    what=updated
  else
    verb=create
    what=created
  fi
  if [ -n "$repo" ]; then
    fossil wiki "$verb" "$name" "$file" -R "$repo" -M markdown
  else
    fossil wiki "$verb" "$name" "$file" -M markdown
  fi
  echo "$what $name"
done
