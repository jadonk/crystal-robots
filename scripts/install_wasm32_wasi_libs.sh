#!/bin/sh
# Installs the wasm32-wasi-libs sysroot (libc, libgc, libpcre2 and the rest
# of what `crystal build --target wasm32-unknown-wasi` needs to link) from
# https://github.com/lbguilherme/wasm-libs, pinned to one release, under
# $WASM32_WASI_LIBS (default ./.wasm32-wasi-libs). Never installed
# globally; scripts/ci.sh's --with-wasm32 step is the only caller.
#
#   scripts/install_wasm32_wasi_libs.sh [VERSION]   # default: see below
#
# The install is a plain tarball extraction: no profile files, no PATH
# changes, nothing outside $WASM32_WASI_LIBS.
set -e

# The only release published as of this writing (2026-09-19); pin it so a
# new release upstream cannot change what CI links against silently.
VERSION="${1:-0.0.3}"
WASM32_WASI_LIBS="${WASM32_WASI_LIBS:-$PWD/.wasm32-wasi-libs}"
ASSET="wasm32-wasi-sysroot.tar.gz"
URL="https://github.com/lbguilherme/wasm-libs/releases/download/${VERSION}/${ASSET}"

echo "Installing wasm32-wasi-libs ${VERSION} into ${WASM32_WASI_LIBS}"

mkdir -p "$WASM32_WASI_LIBS"
tmp_dir=$(mktemp -d -t wasm32-wasi-libs.XXXXXXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT

archive="$tmp_dir/$ASSET"
if command -v curl >/dev/null 2>&1; then
  curl -sSL -o "$archive" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$archive" "$URL"
else
  echo "error: neither curl nor wget is available to download $URL" >&2
  exit 1
fi

tar -xzf "$archive" -C "$tmp_dir"
rm -rf "$WASM32_WASI_LIBS/lib" "$WASM32_WASI_LIBS/include"
mv "$tmp_dir/wasm32-wasi-sysroot/lib" "$WASM32_WASI_LIBS/lib"
mv "$tmp_dir/wasm32-wasi-sysroot/include" "$WASM32_WASI_LIBS/include"

echo "wasm32-wasi-libs ${VERSION} installed: $WASM32_WASI_LIBS/lib/wasm32-wasi"
