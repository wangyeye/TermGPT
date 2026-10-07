#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
if [[ ! -f Assets/TermGPT.icns || Assets/AppIcon.png -nt Assets/TermGPT.icns ]]; then ./scripts/make-icon.sh; fi
source ./scripts/toolchain.sh
swift build -c release "${SWIFT_FLAGS[@]}"
./scripts/package-app.sh
