#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-environment.sh
command -v python3 >/dev/null || { echo '模拟接口需要 Python 3'; exit 1; }
command -v curl >/dev/null || { echo '模拟接口检查需要 curl'; exit 1; }
python3 --version
mkdir -p .build
python3 scripts/mock-provider.py > .build/mock-provider.log 2>&1 &
FIXTURE_PID=$!
cleanup() { kill "$FIXTURE_PID" 2>/dev/null || true; wait "$FIXTURE_PID" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
for i in {1..30}; do
    kill -0 "$FIXTURE_PID" 2>/dev/null || { cat .build/mock-provider.log; exit 1; }
    if curl --silent --max-time 1 http://127.0.0.1:18765/ >/dev/null; then
        TERMGPT_TEST_API=1 ./scripts/test.sh
        exit 0
    fi
    sleep 0.2
done
echo '模拟接口未能启动；请检查本机 18765 端口。'
exit 1
