#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/screen-rpc.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library NotchBuddy/Sources/App/ScreenStore.swift NotchBuddy/Sources/App/RPCProtocol.swift \
    tests/ScreenStoreRPCTests.swift -o "$TEST_DIR/screen-rpc-tests"
"$TEST_DIR/screen-rpc-tests"
