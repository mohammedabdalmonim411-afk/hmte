#!/usr/bin/env bash
#
# EV009: evidence_has_all_plan_ids_but_no_artifacts
#
# Test that gate FAILS when evidence claims plan coverage but has no artifact anchors
#

set -euo pipefail

TEST_NAME="EV009_evidence_has_all_plan_ids_but_no_artifacts"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-EV009
**Version**: 1.0
**Status**: locked

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Feature Implementation | P0 | Core feature |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | test_feature | P-001 | positive |
| T-002 | test_integration | P-001 | positive |

## Acceptance Criteria

| ID | Criterion | Related Plan Item | Verification Method |
|----|-----------|-------------------|---------------------|
| AC-001 | Feature works | S-001 | automated_test |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-EV009",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:evev009",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create evidence with issue: plan_item_ids present but evidence_by_plan_item missing
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:evev009",
    "plan_item_ids": ["S-001", "AC-001", "T-001"]
  },
  "tests_run": ["test_feature"],
  "changed_files": ["src/feature.py"]
}
EOF

# Test: Check evidence anchoring (should FAIL)
echo ""
echo "Test: Check evidence anchoring"

set +e
OUTPUT=$(bash scripts/hmte-check-fidelity.sh \
  --evidence "$TEST_DIR/evidence.json" \
  --plan "$TEST_DIR/test_plan.md" \
  --plan-lock "$TEST_DIR/plan_lock.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(evidence.*anchor|artifact.*missing|no.*evidence.*mapping)"; then
  echo "✅ PASS: Correctly FAILED for evidence_has_all_plan_ids_but_no_artifacts"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL for evidence_has_all_plan_ids_but_no_artifacts"
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
