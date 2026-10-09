#!/bin/bash
# Rebuild only the desktop helper in an existing verified 0.6.0 app archive.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
for tool in python3 cmake clang make perl; do command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }; done
ARCH="${1:-$(uname -m)}"
case "$ARCH" in arm64|x86_64) ;; *) echo 'Unsupported architecture'; exit 1;; esac
ARCHIVE="$PWD/dist/TermGPT-macOS-$ARCH.zip"
[[ -f "$ARCHIVE" ]] || { echo 'Build the full app release first'; exit 1; }
STAGE="$(mktemp -d /private/tmp/termgpt-repack.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto -x -k --norsrc "$ARCHIVE" "$STAGE"
APP="$STAGE/TermGPT.app"
[[ "$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" == 0.6.0 ]] || { echo 'Expected a 0.6.0 package'; exit 1; }
[[ "$(lipo -archs "$APP/Contents/MacOS/TermGPT")" == "$ARCH" ]] || exit 1
./scripts/build-remote-desktop.sh "$ARCH" "$STAGE/helper"
cp -X "$STAGE/helper/TermGPTRemoteDesktop" "$APP/Contents/MacOS/TermGPTRemoteDesktop"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/MacOS/TermGPTRemoteDesktop"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$APP" "$STAGE/TermGPT-macOS-$ARCH.zip"
./scripts/verify-package.sh "$STAGE/TermGPT-macOS-$ARCH.zip" "$ARCH"
python3 scripts/audit-release.py "$STAGE/TermGPT-macOS-$ARCH.zip"
cp -X "$STAGE/TermGPT-macOS-$ARCH.zip" "$ARCHIVE"
echo "Desktop helper repack verified: $ARCH"
