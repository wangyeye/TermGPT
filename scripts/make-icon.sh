#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in sips iconutil; do command -v "$tool" >/dev/null || { echo "缺少工具：$tool，需要 macOS"; exit 1; }; done
[[ -f Assets/AppIcon.png ]] || { echo '缺少源图标 Assets/AppIcon.png'; exit 1; }
ICON_STAGE="$(mktemp -d /private/tmp/termgpt-icon.XXXXXX)"
trap 'rm -rf "$ICON_STAGE"' EXIT
mkdir -p "$ICON_STAGE/TermGPT.iconset"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" Assets/AppIcon.png --out "$ICON_STAGE/TermGPT.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" Assets/AppIcon.png --out "$ICON_STAGE/TermGPT.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_STAGE/TermGPT.iconset" -o "$ICON_STAGE/TermGPT.icns"
cp -X "$ICON_STAGE/TermGPT.icns" Assets/TermGPT.icns
echo '图标生成：Assets/TermGPT.icns'
