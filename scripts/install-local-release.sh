#!/bin/bash
# Install a verified release atomically; quit TermGPT before running this script.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
ARCHIVE="${1:-$PWD/dist/TermGPT-macOS-arm64.zip}"
./scripts/verify-package.sh "$ARCHIVE" "$(uname -m)"
STAGE="$(mktemp -d /Applications/.TermGPT-update.XXXXXX)"
trap 'if [[ -d "$STAGE/Previous.app" && ! -d /Applications/TermGPT.app ]]; then mv "$STAGE/Previous.app" /Applications/TermGPT.app; fi; rm -rf "$STAGE"' EXIT
ditto -x -k --norsrc "$ARCHIVE" "$STAGE"
codesign --verify --deep --strict "$STAGE/TermGPT.app"
if [[ -d /Applications/TermGPT.app ]]; then mv /Applications/TermGPT.app "$STAGE/Previous.app"; fi
mv "$STAGE/TermGPT.app" /Applications/TermGPT.app
codesign --verify --deep --strict /Applications/TermGPT.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/TermGPT.app/Contents/Info.plist
