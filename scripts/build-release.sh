#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
for tool in git python3 shasum strip; do command -v "$tool" >/dev/null || { echo "缺少工具：$tool"; exit 1; }; done
[[ -z "$(git status --porcelain)" ]] || { echo '请先提交发行源码，工作区必须干净'; exit 1; }
python3 scripts/audit-public.py --tracked
RELEASE_ROOT="$PWD"
RELEASE_STAGE="$(mktemp -d /private/tmp/termgpt-release.XXXXXX)"
trap 'rm -rf "$RELEASE_STAGE"' EXIT
# Compile from a source-only archive outside a user's home directory.
git archive HEAD | tar -x -C "$RELEASE_STAGE"
cd "$RELEASE_STAGE"
./scripts/make-icon.sh
source ./scripts/toolchain.sh
mkdir -p "$RELEASE_ROOT/dist"
for TARGET_ARCH in arm64 x86_64; do
    swift build -c release --build-system native --arch "$TARGET_ARCH" "${SWIFT_FLAGS[@]}"
    RELEASE_BIN_DIR="$(swift build -c release --build-system native --arch "$TARGET_ARCH" "${SWIFT_FLAGS[@]}" --show-bin-path)"
    strip -S "$RELEASE_BIN_DIR/TermGPT"
    strip -S "$RELEASE_BIN_DIR/TermGPTSSHAskpass"
    [[ "$(lipo -archs "$RELEASE_BIN_DIR/TermGPTSSHAskpass")" == "$TARGET_ARCH" ]] || { echo "SSH 组件架构不匹配"; exit 1; }
    ./scripts/package-app.sh "$RELEASE_BIN_DIR/TermGPT"
    ./scripts/verify-package.sh "$PWD/dist/TermGPT-macOS-$TARGET_ARCH.zip" "$TARGET_ARCH"
    # Reject user-home paths or typical embedded credentials before upload.
    python3 - "$RELEASE_BIN_DIR/TermGPT" <<'PY'
import pathlib, re, sys
blob = pathlib.Path(sys.argv[1]).read_bytes()
patterns = [rb'/Users/[A-Za-z0-9_.-]+/', rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{30,}', rb'sk-(?:proj-)?[A-Za-z0-9_-]{30,}']
if any(re.search(p, blob) for p in patterns):
    raise SystemExit('发行程序发现个人路径或疑似凭据，停止发布。')
print('发行程序个人路径与凭据模式检查通过。')
PY
    cp -X "dist/TermGPT-macOS-$TARGET_ARCH.zip" "$RELEASE_ROOT/dist/"
done
python3 "$RELEASE_ROOT/scripts/audit-release.py" "$RELEASE_ROOT/dist/TermGPT-macOS-arm64.zip" "$RELEASE_ROOT/dist/TermGPT-macOS-x86_64.zip"
cd "$RELEASE_ROOT/dist"
shasum -a 256 TermGPT-macOS-arm64.zip TermGPT-macOS-x86_64.zip > SHA256SUMS
shasum -a 256 -c SHA256SUMS
