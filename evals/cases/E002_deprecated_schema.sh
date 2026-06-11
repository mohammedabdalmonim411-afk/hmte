#!/usr/bin/env bash
# E002_deprecated_schema.sh — Test: deprecated fields → WARN/FAIL by mode

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$PROJECT_ROOT/evals/fixtures/deprecated_schema"

# Test default mode (should WARN but exit 0)
OUTPUT=$(bash "$PROJECT_ROOT/scripts/hmte-validate-phases.sh" "$FIXTURE_DIR/phases.json" 2>&1)
if echo "$OUTPUT" | grep -q "WARN"; then
    echo "PASS (default): deprecated fields triggered WARN"
else
    echo "FAIL (default): should have warned about deprecated fields"
    echo "OUTPUT: $OUTPUT"
    exit 1
fi

# Test release mode (should FAIL)
if HMTE_LINT_MODE=release bash "$PROJECT_ROOT/scripts/hmte-validate-phases.sh" "$FIXTURE_DIR/phases.json" 2>/dev/null; then
    echo "FAIL (release): should have rejected deprecated fields"
    exit 1
else
    echo "PASS (release): deprecated fields correctly rejected"
    exit 0
fi
