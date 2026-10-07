#!/bin/bash
# Source from scripts after changing to the project root. Keep caches in this workspace.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/cache"
SWIFT_FLAGS=(--disable-sandbox --cache-path "$PWD/.build/cache" --manifest-cache local)
PLUGIN_DIR=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
if [[ -f "$PLUGIN_DIR/libSwiftUIMacros.dylib" ]]; then
    SWIFT_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR")
fi
# Command Line Tools omit XCTest; reuse the installed Xcode platform test frameworks.
TEST_FRAMEWORKS=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks
TEST_LIBS=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib
TEST_SWIFT_FLAGS=()
if [[ -d "$TEST_FRAMEWORKS/XCTest.framework" ]]; then
    TEST_SWIFT_FLAGS=(-Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" -Xswiftc -I -Xswiftc "$TEST_LIBS" -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" -Xlinker -L -Xlinker "$TEST_LIBS" -Xlinker -rpath -Xlinker "$TEST_LIBS")
fi
