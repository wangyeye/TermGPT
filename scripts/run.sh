#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
[[ -x dist/TermGPT.app/Contents/MacOS/TermGPT ]] || ./scripts/build.sh
open "$PWD/dist/TermGPT.app"
