#!/bin/bash
# Reuse audited Swift binaries only when app sources still match their build commit.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
BASE="${1:?Usage: scripts/repackage-desktop-fix.sh original-build-commit}"
git diff --exit-code "$BASE" HEAD -- Sources Package.swift Assets scripts/package-app.sh Vendor
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit final source before packaging'; exit 1; }
python3 scripts/audit-public.py --tracked
(cd dist; shasum -a 256 -c SHA256SUMS)
STAGE="$(mktemp -d /private/tmp/termgpt-repackage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
for ARCH in arm64 x86_64; do
 ./scripts/verify-package.sh "$PWD/dist/TermGPT-macOS-$ARCH.zip" "$ARCH"
 mkdir -p "$STAGE/$ARCH"
 ditto -x -k --norsrc "dist/TermGPT-macOS-$ARCH.zip" "$STAGE/$ARCH"
 ./scripts/package-app.sh "$STAGE/$ARCH/TermGPT.app/Contents/MacOS/TermGPT"
 ./scripts/verify-package.sh "$PWD/dist/TermGPT-macOS-$ARCH.zip" "$ARCH"
done
python3 scripts/audit-release.py dist/TermGPT-macOS-arm64.zip dist/TermGPT-macOS-x86_64.zip
python3 scripts/package-remote-source.py
(cd dist; shasum -a 256 TermGPT-macOS-arm64.zip TermGPT-macOS-x86_64.zip TermGPT-RemoteDesktop-source.tar.gz > SHA256SUMS; shasum -a 256 -c SHA256SUMS)
