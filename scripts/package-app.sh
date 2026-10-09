#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
PACKAGE_STAGE="$(mktemp -d /private/tmp/termgpt-package.XXXXXX)"
trap 'rm -rf "$PACKAGE_STAGE"' EXIT
APP="$PACKAGE_STAGE/TermGPT.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ -n "${1:-}" ]]; then
    APP_BINARY="$1"
    [[ -x "$APP_BINARY" ]] || { echo "缺少 release 程序"; exit 1; }
elif [[ -x .build/out/Products/Release/TermGPT ]]; then
    APP_BINARY="$PWD/.build/out/Products/Release/TermGPT"
elif [[ -x .build/release/TermGPT ]]; then
    APP_BINARY="$PWD/.build/release/TermGPT"
else
    echo '缺少 release 程序，请先运行 scripts/build.sh'; exit 1
fi
PACKAGE_ARCH="$(lipo -archs "$APP_BINARY")"
case "$PACKAGE_ARCH" in arm64|x86_64) ;; *) echo "不支持的发行架构"; exit 1;; esac
cp -X "$APP_BINARY" "$APP/Contents/MacOS/TermGPT"
ASKPASS_BINARY="$(dirname "$APP_BINARY")/TermGPTSSHAskpass"
[[ -x "$ASKPASS_BINARY" ]] || { echo '缺少 SSH 密码认证组件'; exit 1; }
cp -X "$ASKPASS_BINARY" "$APP/Contents/MacOS/TermGPTSSHAskpass"
./scripts/build-zmodem.sh "$PACKAGE_ARCH" "$(dirname "$APP_BINARY")"
for component in TermGPTRZ TermGPTSZ; do
    cp -X "$(dirname "$APP_BINARY")/$component" "$APP/Contents/MacOS/$component"
    codesign --force --sign - "$APP/Contents/MacOS/$component"
done
cp -X Vendor/lrzsz/COPYING "$APP/Contents/Resources/lrzsz-COPYING.txt"
./scripts/build-remote-desktop.sh "$PACKAGE_ARCH" "$(dirname "$APP_BINARY")"
cp -X "$(dirname "$APP_BINARY")/TermGPTRemoteDesktop" "$APP/Contents/MacOS/TermGPTRemoteDesktop"
codesign --force --sign - "$APP/Contents/MacOS/TermGPTRemoteDesktop"
for license in NOTICE FreeRDP-LICENSE LibVNC-COPYING OpenSSL-LICENSE GPL-3.0; do
    cp -X "Vendor/RemoteDesktop/$license.txt" "$APP/Contents/Resources/RemoteDesktop-$license.txt"
done
cp -X Assets/TermGPT.icns "$APP/Contents/Resources/TermGPT.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TermGPT</string>
<key>CFBundleIdentifier</key><string>local.TermGPT.desktop</string>
<key>CFBundleName</key><string>TermGPT</string>
<key>CFBundleDisplayName</key><string>TermGPT</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>14</string>
<key>CFBundleIconFile</key><string>TermGPT</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
# Finder/File Provider metadata in this workspace cannot be included in a signature.
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/MacOS/TermGPTSSHAskpass"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$PWD/dist"
/usr/bin/ditto --norsrc --noextattr "$APP" "$PWD/dist/TermGPT.app"
/usr/bin/ditto --norsrc --noextattr -c -k --keepParent "$APP" "$PWD/dist/TermGPT-macOS-$PACKAGE_ARCH.zip"
echo "App：$PWD/dist/TermGPT.app"
echo "签名验证通过的 ZIP：$PWD/dist/TermGPT-macOS-$PACKAGE_ARCH.zip"
