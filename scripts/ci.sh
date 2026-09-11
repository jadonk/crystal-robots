#!/bin/sh
# The one CI command: everything the task pipeline, trunk-ops and a
# developer run before trusting a revision. Exits non-zero on any failure.
#
#   scripts/ci.sh                 # build docs, build, spec, format, examples
#   scripts/ci.sh --with-wasmer   # also run the WebAssembly specs under wasmer 4.4.0,
#                                 # installing it under ./.wasmer when absent
#
# Without --with-wasmer the wasmer specs are reported as pending with their
# reason; they are never a tolerated failure.
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
# Without it the shipped binary reports "unknown" for --version and /version,
# which defeats comparing a deploy against trunk, so the release build (this
# one) refuses to ship that way; `crystal build`/`shards build` run by hand
# outside ci.sh still fall back to "unknown", which is fine for local dev.
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
    # Every write stays inside the checkout: the installer appends its shell
    # snippet to $PROFILE (when that file exists), downloads through
    # mktemp -t (honours $TMPDIR), and prompts if a stale bin/wasmer is
    # found, so a partial install is cleared first.
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

step "example robots build natively with the prelude"
mkdir -p bin
for robot in examples/*.cr; do
  name="$(basename "$robot" .cr)"
  (cd examples && crystal build --prelude=../src/prelude "$name.cr" -o "../bin/example-$name")
done

step "CLI smoke"
bin/crystal-robots -v >/dev/null
bin/crystal-robots -t examples/test.cr >/dev/null
bin/crystal-robots -c examples/test.cr -o bin/test.wasm
bin/crystal-robots -m 1 -l 3000 examples/counter.cr examples/target.cr >/dev/null

printf '\n== ci.sh: all green%s\n' "$([ "$with_wasmer" = 1 ] && echo ' (with wasmer)')"
