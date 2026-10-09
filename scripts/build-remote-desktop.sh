#!/bin/bash
# Build embedded desktop engines from checksum-pinned sources, with no Homebrew runtime dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in cmake clang make perl python3 lipo; do command -v "$tool" >/dev/null || { echo "Missing build tool: $tool"; exit 1; }; done
ARCH="${1:-$(uname -m)}"
REMOTE_TESTS="${3:-OFF}"
OUTPUT="${2:-$PWD/.build/remote-$ARCH}"
case "$ARCH" in arm64) PLATFORM=darwin64-arm64-cc;; x86_64) PLATFORM=darwin64-x86_64-cc;; *) echo 'Unsupported architecture'; exit 1;; esac
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
python3 scripts/fetch-remote-deps.py
SDK="$PWD/.build/remote-sdk-$ARCH-openssl-3.6.5-static-v3"
if [[ ! -f "$SDK/lib/libssl.a" ]]; then
 STAGE="$(mktemp -d /private/tmp/termgpt-openssl.XXXXXX)"
 trap 'rm -rf "${STAGE:-}"' EXIT
 cp -R .build/remote-sources/openssl "$STAGE/source"
 (cd "$STAGE/source"; ./Configure "$PLATFORM" no-shared no-module no-tests --prefix=/termgpt-sdk --openssldir=/etc/ssl -mmacosx-version-min=13.0 "-ffile-prefix-map=$STAGE=."; make -j8; make DESTDIR="$STAGE/install" install_sw; mkdir -p "$SDK"; cp -R "$STAGE/install/termgpt-sdk/"* "$SDK/") > "$OUTPUT/openssl-build.log" 2>&1
 rm -rf "$STAGE"
fi
STAGE="$(mktemp -d /private/tmp/termgpt-remote.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/source"
cp -R Native/RemoteDesktop "$STAGE/native"
cp -R .build/remote-sources/freerdp .build/remote-sources/libvnc "$STAGE/source/"
python3 "$STAGE/native/patch-libvnc.py" "$STAGE/source/libvnc"
python3 "$STAGE/native/patch-freerdp.py" "$STAGE/source/freerdp"
cmake -S "$STAGE/native" -B "$STAGE/build" -DREMOTE_TESTS="$REMOTE_TESTS" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_EXPORT_PACKAGE_REGISTRY=OFF -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DREMOTE_SOURCES="$STAGE/source" -DOPENSSL_ROOT_DIR="$SDK" -DOPENSSL_USE_STATIC_LIBS=TRUE -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew -DCMAKE_C_FLAGS="-ffile-prefix-map=$STAGE=." -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$STAGE=." > "$OUTPUT/remote-build.log" 2>&1
cmake --build "$STAGE/build" --target TermGPTRemoteDesktop -j8 >> "$OUTPUT/remote-build.log" 2>&1
cp -X "$STAGE/build/TermGPTRemoteDesktop" "$OUTPUT/TermGPTRemoteDesktop"
strip -S "$OUTPUT/TermGPTRemoteDesktop"
if [[ "$REMOTE_TESTS" == ON ]]; then
 cmake --build "$STAGE/build" --target TermGPTRDPFixture -j8 >> "$OUTPUT/remote-build.log" 2>&1
 cp -X "$STAGE/build/TermGPTRDPFixture" "$OUTPUT/TermGPTRDPFixture"
fi
[[ "$(lipo -archs "$OUTPUT/TermGPTRemoteDesktop")" == "$ARCH" ]]
echo "Embedded desktop helper built: $ARCH"
