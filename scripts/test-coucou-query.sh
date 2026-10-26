#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-query.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/NoteModels.swift NotchBuddy/Sources/App/NoteEcho.swift \
    NotchBuddy/Sources/App/CoucouQuery.swift tests/CoucouQueryTests.swift -o "$TEST_DIR/coucou-query-tests"
"$TEST_DIR/coucou-query-tests"
