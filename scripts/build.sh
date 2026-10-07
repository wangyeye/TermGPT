#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
[[ -f Assets/TermGPT.icns ]] || ./scripts/make-icon.sh
source ./scripts/toolchain.sh
swift build -c release "${SWIFT_FLAGS[@]}"
./scripts/package-app.sh
