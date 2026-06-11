#!/usr/bin/env bash
# E011_audit_pack_invalid_mode.sh — Test: Audit pack MUST FAIL with invalid mode
#
# Verifies that hmte-audit-pack.sh rejects invalid modes with exit 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_ROOT"

# Test 1: Invalid mode
OUTPUT=$(bash scripts/hmte-audit-pack.sh --mode invalid 2>&1) || EXIT_CODE=$?

if [ "${EXIT_CODE:-0}" -ne 1 ]; then
    echo "FAIL: Audit pack should exit 1 with invalid mode, got ${EXIT_CODE:-0}"
    echo "Output: $OUTPUT"
    exit 1
fi

if ! echo "$OUTPUT" | grep -qi "invalid"; then
    echo "FAIL: Audit pack output should mention 'invalid'"
    echo "Output: $OUTPUT"
    exit 1
fi

# Test 2: Missing mode
OUTPUT=$(bash scripts/hmte-audit-pack.sh 2>&1) || EXIT_CODE=$?

if [ "${EXIT_CODE:-0}" -ne 1 ]; then
    echo "FAIL: Audit pack should exit 1 with missing mode, got ${EXIT_CODE:-0}"
    echo "Output: $OUTPUT"
    exit 1
fi

echo "PASS: Audit pack correctly rejects invalid/missing mode"
exit 0
