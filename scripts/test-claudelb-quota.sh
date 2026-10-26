#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-claudelb-quota.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ClaudeLBQuota.swift NotchBuddy/Sources/App/ClaudePlanGauge.swift \
    tests/ClaudeLBQuotaTests.swift -o "$TEST_DIR/claudelb-quota-tests"
"$TEST_DIR/claudelb-quota-tests"
