#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
ARCHIVE="${1:-$PWD/dist/TermGPT-macOS-arm64.zip}"
[[ -f "$ARCHIVE" ]] || { echo "缺少安装包：$ARCHIVE"; exit 1; }
VERIFY_STAGE="$(mktemp -d /private/tmp/termgpt-verify.XXXXXX)"
trap 'rm -rf "$VERIFY_STAGE"' EXIT
/usr/bin/ditto -x -k --norsrc "$ARCHIVE" "$VERIFY_STAGE"
plutil -lint "$VERIFY_STAGE/TermGPT.app/Contents/Info.plist"
codesign --verify --deep --strict "$VERIFY_STAGE/TermGPT.app"
file "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/TermGPT"
echo 'ZIP 解压、应用格式与签名验证通过'
