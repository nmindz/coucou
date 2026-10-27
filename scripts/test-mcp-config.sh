#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mcp-config.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/CoucouMCPInstall.swift NotchBuddy/Sources/App/CoucouMCPScreen.swift \
    tests/MCPConfigEditTests.swift -o "$TEST_DIR/mcp-config-tests"
"$TEST_DIR/mcp-config-tests"
