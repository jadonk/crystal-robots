#!/bin/sh
# The one CI command: everything a developer, or a coordinator's own
# pipeline, runs before trusting a revision. Exits non-zero on any
# failure.
#
#   scripts/ci.sh                # build docs, build, spec, format
#   scripts/ci.sh --with-wasmer  # also run the WebAssembly specs under wasmer 4.4.0,
#                                # installing it under ./.wasmer when absent
#
# Without --with-wasmer the wasmer specs are reported as pending with
# their own reason; that is never a tolerated failure, only a signal
# this machine has no libwasmer. There is no --with-wasm32 yet: the
# browser-hosted compiler has not been replayed onto this history (it
# waits for its own directive).
set -e
cd "$(dirname "$0")/.."
with_wasmer=0
for arg in "$@"; do
  case "$arg" in
    --with-wasmer) with_wasmer=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n== %s\n' "$*"; }

step "shards install"
shards install --without-development >/dev/null 2>&1 || shards install

step "bootstrap build"
shards build

step "build-docs (before the final build, so the binary embeds them)"
bin/crystal-robots build-docs

step "check manifest.uuid"
# Without it the shipped binary reports "unknown" for --version and
# /version, which defeats comparing a deploy against a specific
# check-in, so the release build (this one) refuses to ship that way;
# crystal build/shards build run by hand outside ci.sh still falls
# back to "unknown", which is fine for local dev. A plain git clone
# (a mirror with no Fossil checkout behind it) never has manifest.uuid
# either, since it is a Fossil checkout artifact, not a versioned
# file (.fossil-settings/ignore-glob); fall back to the git commit
# HEAD is on there instead of failing outright.
if [ ! -s manifest.uuid ] && [ -d .git ]; then
  git rev-parse HEAD >manifest.uuid
fi
if [ ! -s manifest.uuid ]; then
  echo "manifest.uuid is missing or empty; run 'fossil setting manifest on' and check out from Fossil so the release build carries a check-in" >&2
  exit 1
fi

step "shards build"
shards build

spec_flags=""
if [ "$with_wasmer" = 1 ]; then
  step "wasmer 4.4.0"
  export WASMER_DIR="$PWD/.wasmer"
  if [ ! -x "$WASMER_DIR/bin/wasmer" ] || [ ! -f "$WASMER_DIR/lib/libwasmer.a" ]; then
    # Every write stays inside the checkout: the installer appends its
    # shell snippet to $PROFILE (when that file exists), downloads
    # through mktemp -t (honours $TMPDIR), and prompts if a stale
    # bin/wasmer is found, so a partial install is cleared first.
    rm -rf ./.wasmer
    mkdir -p "$WASMER_DIR/tmp"
    : > "$WASMER_DIR/profile.sh"
    PROFILE="$WASMER_DIR/profile.sh" TMPDIR="$WASMER_DIR/tmp" WASMER_INSTALL_LOG=quiet \
      sh scripts/install_wasmer.sh v4.4.0
    rm -rf "$WASMER_DIR/tmp"
  fi
  export PATH="$WASMER_DIR/bin:$PATH"
  "$WASMER_DIR/bin/wasmer" --version
  spec_flags="-Dwasmer"
fi

step "crystal spec $spec_flags"
crystal spec $spec_flags

step "crystal tool format --check"
crystal tool format --check src spec scripts

step "CLI smoke"
bin/crystal-robots -v >/dev/null
bin/crystal-robots -t examples/hello.cr >/dev/null
bin/crystal-robots -c examples/hello.cr -o bin/smoke.wasm
bin/crystal-robots -m 1 -l 3000 examples/counter.cr examples/target.cr >/dev/null

printf '\n== ci.sh: all green%s\n' "$([ "$with_wasmer" = 1 ] && echo ' (with wasmer)')"
