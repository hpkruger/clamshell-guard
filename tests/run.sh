#!/bin/bash
set -euo pipefail

REPOSITORY="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TEMP="$(mktemp -d /tmp/clamshell-guard-test.XXXXXX)"
ROUTER_PID=""

cleanup() {
    if [[ -n "$ROUTER_PID" ]]; then
        kill "$ROUTER_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_TEMP"
}
trap cleanup EXIT

swiftc -Onone -g -framework IOKit \
    -o "$TEST_TEMP/SystemSleepAssertionTests" \
    "$REPOSITORY/SystemSleepAssertion.swift" \
    "$REPOSITORY/tests/SystemSleepAssertionTests.swift"

"$TEST_TEMP/SystemSleepAssertionTests"

swiftc -Onone -g -framework IOKit \
    -o "$TEST_TEMP/ClamshellDisplaySleepControllerTests" \
    "$REPOSITORY/ClamshellDisplaySleepController.swift" \
    "$REPOSITORY/tests/ClamshellDisplaySleepControllerTests.swift"

"$TEST_TEMP/ClamshellDisplaySleepControllerTests"

python3 "$REPOSITORY/tests/fake_codex_router.py" "$TEST_TEMP/codex-home" &
ROUTER_PID=$!

for _ in {1..100}; do
    [[ -f "$TEST_TEMP/codex-home/ready" ]] && break
    sleep 0.05
done
[[ -f "$TEST_TEMP/codex-home/ready" ]]

swiftc -Onone -g -lsqlite3 \
    -o "$TEST_TEMP/CodexIPCMonitorIntegration" \
    "$REPOSITORY/CodexIPCMonitor.swift" \
    "$REPOSITORY/tests/CodexIPCMonitorIntegration.swift"

"$TEST_TEMP/CodexIPCMonitorIntegration" "$TEST_TEMP/codex-home"
wait "$ROUTER_PID"
ROUTER_PID=""
