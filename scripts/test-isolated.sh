#!/bin/bash
# Compile a stable source snapshot when File Provider changes file timestamps.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
STAGE="$(mktemp -d /private/tmp/termgpt-isolated-tests.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/source"
tar --exclude=.git --exclude=.build --exclude=dist -cf - . | tar -xf - -C "$STAGE/source"
cd "$STAGE/source"
./scripts/test.sh
