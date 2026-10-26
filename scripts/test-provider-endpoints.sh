#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-provider-endpoints.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ProviderEndpoint.swift \
    tests/ProviderEndpointTests.swift -o "$TEST_DIR/provider-endpoint-tests"
"$TEST_DIR/provider-endpoint-tests"
