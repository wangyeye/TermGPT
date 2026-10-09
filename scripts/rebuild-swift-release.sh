#!/bin/bash
# Rebuild Swift-only packaging fixes using verified, unchanged native helpers.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
BASE="${1:?Usage: scripts/rebuild-swift-release.sh verified-package-build-commit}"
for tool in git python3 shasum codesign lipo ditto strip; do command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }; done
git rev-parse --verify "$BASE^{commit}" >/dev/null
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit source before rebuilding'; exit 1; }
# Native helper sources, licenses, assets and package metadata must match the audited packages.
git diff --exit-code "$BASE" HEAD -- Native Vendor/RemoteDesktop Vendor/lrzsz Assets Package.swift scripts/package-app.sh scripts/build-remote-desktop.sh scripts/build-zmodem.sh scripts/fetch-remote-deps.py
python3 scripts/audit-public.py --tracked
(cd dist; shasum -a 256 -c SHA256SUMS)
ROOT="$PWD"
STAGE="$(mktemp -d /private/tmp/termgpt-swift-fix.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/source" "$STAGE/archives" "$STAGE/output"
git archive HEAD | tar -x -C "$STAGE/source"
for ARCH in arm64 x86_64; do
    ./scripts/verify-package.sh "$ROOT/dist/TermGPT-macOS-$ARCH.zip" "$ARCH"
    cp -X "$ROOT/dist/TermGPT-macOS-$ARCH.zip" "$STAGE/archives/"
done
cd "$STAGE/source"
source scripts/toolchain.sh
for ARCH in arm64 x86_64; do
    swift build -c release --build-system native --arch "$ARCH" "${SWIFT_FLAGS[@]}"
    BIN="$(swift build -c release --build-system native --arch "$ARCH" "${SWIFT_FLAGS[@]}" --show-bin-path)"
    mkdir -p "$STAGE/$ARCH"
    ditto -x -k --norsrc "$STAGE/archives/TermGPT-macOS-$ARCH.zip" "$STAGE/$ARCH"
    APP="$STAGE/$ARCH/TermGPT.app"
    for COMPONENT in TermGPT TermGPTSSHAskpass; do
        [[ "$(lipo -archs "$BIN/$COMPONENT")" == "$ARCH" ]]
        strip -S "$BIN/$COMPONENT"
        cp -X "$BIN/$COMPONENT" "$APP/Contents/MacOS/$COMPONENT"
        codesign --force --sign - "$APP/Contents/MacOS/$COMPONENT"
    done
    xattr -cr "$APP"
    codesign --force --sign - "$APP"
    codesign --verify --deep --strict "$APP"
    ditto --norsrc --noextattr -c -k --keepParent "$APP" "$STAGE/output/TermGPT-macOS-$ARCH.zip"
    "$ROOT/scripts/verify-package.sh" "$STAGE/output/TermGPT-macOS-$ARCH.zip" "$ARCH"
done
python3 "$ROOT/scripts/audit-release.py" "$STAGE/output/TermGPT-macOS-arm64.zip" "$STAGE/output/TermGPT-macOS-x86_64.zip"
for ARCH in arm64 x86_64; do cp -X "$STAGE/output/TermGPT-macOS-$ARCH.zip" "$ROOT/dist/"; done
cd "$ROOT"
python3 scripts/package-remote-source.py
(cd dist; shasum -a 256 TermGPT-macOS-arm64.zip TermGPT-macOS-x86_64.zip TermGPT-RemoteDesktop-source.tar.gz > SHA256SUMS; shasum -a 256 -c SHA256SUMS)
