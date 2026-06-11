#!/usr/bin/env bash
#
# PD009: vague_plan_item_rejected
#
# Test that plan validation FAILS on vague plan items without concrete verification
#

set -euo pipefail

TEST_NAME="PD009_vague_plan_item_rejected"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-PD009
**Version**: 1.0
**Status**: locked

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Improve system | P0 | Make it better |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | test_1 | P-001 | positive |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-PD009",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:testpd009",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create evidence with issue: no verification_method, no required_steps
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:testpd009",
    "plan_item_ids": ["S-001"]
  },
  "tests_run": ["partial_test"],
  "changed_files": ["src/partial.py"]
}
EOF

# Test: Check plan-contract (should FAIL)
echo ""
echo "Test: Check plan-contract"

set +e
OUTPUT=$(bash scripts/hmte-plan-contract.sh \
  --plan "$TEST_DIR/test_plan.md" \
  --validate 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(vague|incomplete|missing.*verification)"; then
  echo "✅ PASS: Correctly FAILED for vague_plan_item_rejected"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL for vague_plan_item_rejected"
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
