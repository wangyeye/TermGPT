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
git diff --exit-code "$BASE" HEAD -- Native Vendor/RemoteDesktop Vendor/lrzsz Assets Package.swift scripts/build-remote-desktop.sh scripts/build-zmodem.sh scripts/fetch-remote-deps.py
# Reusing native helpers allows only the two bundle version fields to change.
python3 - "$BASE" <<'PYVERSION'
import pathlib, re, subprocess, sys
current = pathlib.Path('scripts/package-app.sh').read_text()
previous = subprocess.check_output(['git','show',sys.argv[1]+':scripts/package-app.sh'], text=True)
pattern = r'(<key>CFBundle(?:ShortVersionString|Version)</key><string>)[0-9.]+(</string>)'
def normalized(text):
    value, count = re.subn(pattern, r'\1VERSION\2', text)
    if count != 2: raise SystemExit('Expected two package version fields')
    return value
if normalized(current) != normalized(previous): raise SystemExit('Package script changed beyond version fields; use full release build')
PYVERSION
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
    python3 - "$APP/Contents/Info.plist" scripts/package-app.sh <<'PYVERSION'
import pathlib, plistlib, re, sys
path=pathlib.Path(sys.argv[1]); data=plistlib.loads(path.read_bytes()); source=pathlib.Path(sys.argv[2]).read_text()
for key in ['CFBundleShortVersionString','CFBundleVersion']:
    data[key]=re.search(r'<key>'+key+r'</key><string>([0-9.]+)</string>',source).group(1)
path.write_bytes(plistlib.dumps(data))
PYVERSION
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
