#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
source ./scripts/toolchain.sh
RUNNER=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest
[[ -x "$RUNNER" ]] || { echo '自动测试需要已安装完整 Xcode 的 XCTest runner；App 构建不需要接受 Xcode 许可。'; exit 1; }
# Native build avoids SwiftBuild signing temporary test bundles in File Provider folders.
swift build --build-tests --build-system native "${SWIFT_FLAGS[@]}" "${TEST_SWIFT_FLAGS[@]}"
TEST_BUNDLE="$PWD/.build/debug/TermGPTPackageTests.xctest"
[[ -d "$TEST_BUNDLE" ]] || { echo '没有找到测试 bundle'; exit 1; }
TEST_STAGE="$(mktemp -d /private/tmp/termgpt-test.XXXXXX)"
trap 'rm -rf "$TEST_STAGE"' EXIT
/usr/bin/ditto --norsrc --noextattr "$TEST_BUNDLE" "$TEST_STAGE/TermGPTPackageTests.xctest"
xattr -cr "$TEST_STAGE/TermGPTPackageTests.xctest"
codesign --force --sign - "$TEST_STAGE/TermGPTPackageTests.xctest"
"$RUNNER" "$TEST_STAGE/TermGPTPackageTests.xctest"
