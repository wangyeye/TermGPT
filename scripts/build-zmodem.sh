#!/bin/bash
# Build the separately licensed upstream ZMODEM helpers for one app architecture.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS required'; exit 1; }
for tool in clang make; do command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }; done
TARGET_ARCH="${1:-$(uname -m)}"
OUTPUT_DIR="${2:-$PWD/.build/zmodem-$TARGET_ARCH}"
case "$TARGET_ARCH" in arm64) HOST=aarch64-apple-darwin;; x86_64) HOST=x86_64-apple-darwin;; *) exit 1;; esac
STAGE="$(mktemp -d /private/tmp/termgpt-zmodem.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
cp -R Vendor/lrzsz "$STAGE/source"
cd "$STAGE/source"
MACOSX_DEPLOYMENT_TARGET=13.0 CC=clang CFLAGS="-O2 -arch $TARGET_ARCH -mmacosx-version-min=13.0" LDFLAGS="-arch $TARGET_ARCH" ./configure --host="$HOST" --disable-nls --disable-Werror --disable-mkdir > "$STAGE/configure.log" 2>&1 || { tail -n 30 "$STAGE/configure.log"; exit 1; }
make -C src -j4 lrz lsz > "$STAGE/make.log" 2>&1 || { tail -n 30 "$STAGE/make.log"; exit 1; }
mkdir -p "$OUTPUT_DIR"
cp src/lrz "$OUTPUT_DIR/TermGPTRZ"
cp src/lsz "$OUTPUT_DIR/TermGPTSZ"
strip -S "$OUTPUT_DIR/TermGPTRZ" "$OUTPUT_DIR/TermGPTSZ"
echo "ZMODEM helpers built: $TARGET_ARCH"
