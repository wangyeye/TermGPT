#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo '需要 macOS'; exit 1; }
for tool in swift codesign plutil xattr lipo ditto; do command -v "$tool" >/dev/null || { echo "缺少工具：$tool。请安装 Xcode Command Line Tools。"; exit 1; }; done
[[ -x /usr/bin/ssh && -x /bin/zsh ]] || { echo '缺少系统 SSH 或 zsh'; exit 1; }
[[ -f Vendor/SwiftTerm/Package.swift ]] || { echo '缺少 Vendor/SwiftTerm 依赖'; exit 1; }
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[[ "$OS_MAJOR" -ge 13 ]] || { echo '需要 macOS 13 或更新版本'; exit 1; }
swift --version
printf '架构：%s\nmacOS：%s\n' "$(uname -m)" "$(sw_vers -productVersion)"
echo '环境检查通过。AI 可连接 ChatGPT 或配置 Other Providers。'
