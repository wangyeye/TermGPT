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
if [[ -n "${2:-}" ]]; then
    [[ "$(lipo -archs "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/TermGPT")" == "$2" ]] || { echo "发行架构不匹配"; exit 1; }
fi
[[ -x "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/TermGPTSSHAskpass" ]] || { echo "缺少 SSH 密码登录组件"; exit 1; }
if [[ -n "${2:-}" ]]; then
    [[ "$(lipo -archs "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/TermGPTSSHAskpass")" == "$2" ]] || { echo "SSH 组件架构不匹配"; exit 1; }
fi
file "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/TermGPT"
echo 'ZIP 解压、应用格式与签名验证通过'

for component in TermGPTRZ TermGPTSZ TermGPTRemoteDesktop; do
    [[ -x "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/$component" ]] || { echo 'Missing ZMODEM helper'; exit 1; }
    codesign --verify --strict "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/$component"
    if [[ -n "${2:-}" ]]; then
        [[ "$(lipo -archs "$VERIFY_STAGE/TermGPT.app/Contents/MacOS/$component")" == "$2" ]] || exit 1
    fi
done
