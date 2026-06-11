#!/usr/bin/env bash
#
# PD010: phases_json_drops_locked_plan_item
#
# Test that gate FAILS when phases.json omits locked plan items
#

set -euo pipefail

TEST_NAME="PD010_phases_json_drops_locked_plan_item"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-PD010
**Version**: 1.0
**Status**: locked

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Feature A | P0 |
| S-002 | Feature B | P0 |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | test_1 | P-001 | positive |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-PD010",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:testpd010",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create evidence with issue: phases.json only references S-001
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:testpd010",
    "plan_item_ids": ["S-001"]
  },
  "tests_run": ["partial_test"],
  "changed_files": ["src/partial.py"]
}
EOF

# Test: Check fidelity (should FAIL)
echo ""
echo "Test: Check fidelity"

set +e
OUTPUT=$(bash scripts/hmte-check-fidelity.sh \
  --evidence "$TEST_DIR/evidence.json" \
  --plan "$TEST_DIR/test_plan.md" \
  --plan-lock "$TEST_DIR/plan_lock.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(missing.*plan.*item|dropped.*item|incomplete.*coverage)"; then
  echo "✅ PASS: Correctly FAILED for phases_json_drops_locked_plan_item"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL for phases_json_drops_locked_plan_item"
  echo "   Exit code: $EXIT_CODE"
  echo "   Output: $OUTPUT"
  RESULT=1
fi

# Cleanup
rm -rf "$TEST_DIR"

echo "════════════════════════════════════════════════════════════════"
if [ $RESULT -eq 0 ]; then
  echo "✅ Test $TEST_NAME: PASS"
else
  echo "❌ Test $TEST_NAME: FAIL"
fi

exit $RESULT
