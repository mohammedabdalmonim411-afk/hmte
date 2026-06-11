#!/usr/bin/env bash
# E003_valid_sequential.sh — Test: 合法 sequential → validation PASS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$PROJECT_ROOT/evals/fixtures/valid_sequential"

# Test validation (should PASS)
if bash "$PROJECT_ROOT/scripts/hmte-validate-phases.sh" "$FIXTURE_DIR/phases.json" 2>&1 | grep -q "PASS"; then
    echo "PASS: valid sequential schema accepted"
    exit 0
else
    echo "FAIL: valid sequential schema should pass"
    exit 1
fi
