#!/usr/bin/env bash
# PC003_plan_item_without_id_fails.sh — Test: Plan item without ID → validation FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

# Create invalid plan contract (missing IDs in scope table)
cat > invalid_plan.md << 'EOF'
# Plan Contract

**Plan ID**: TEST-PLAN-v1.0-20260610
**Version**: 1.0
**Project**: Test Project
**Status**: draft

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| | Feature A | P0 | Missing ID |
| S-002 | Feature B | P1 | Has ID |

## Non-Scope

| ID | Item | Reason |
|----|------|--------|
| NS-001 | Feature C | Out of scope |

## Phases

| ID | Phase | Goal | Plan Items |
|----|-------|------|------------|
| P-001 | Phase 1 | Test | S-002 |
EOF

# Run plan contract validation - should FAIL due to missing ID
OUTPUT=$(bash "$PROJECT_ROOT/scripts/hmte-plan-contract.sh" --plan invalid_plan.md 2>&1) || VALIDATION_EXIT=$?

# Check exit code
if [ "${VALIDATION_EXIT:-0}" -eq 0 ]; then
    echo "FAIL: plan contract validation should have failed with missing ID"
    echo "Output: $OUTPUT"
    exit 1
fi

# Check failure reason mentions missing or invalid ID
if echo "$OUTPUT" | grep -qE "ID|格式|missing|invalid"; then
    echo "PASS: plan contract validation correctly failed due to missing ID"
    exit 0
else
    echo "FAIL: plan contract validation failed for wrong reason"
    echo "Output: $OUTPUT"
    exit 1
fi
