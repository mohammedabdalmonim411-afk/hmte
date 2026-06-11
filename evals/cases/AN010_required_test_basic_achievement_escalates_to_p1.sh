#!/usr/bin/env bash
#
# AN010: required_test_basic_achievement_escalates_to_p1
#
# Test that 'basic achievement' on required test escalates from P2 to P1
#

set -euo pipefail

TEST_NAME="AN010_required_test_basic_achievement_escalates_to_p1"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-AN010
**Version**: 1.0
**Status**: locked

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | integration_test | P-001 | positive |
| T-002 | performance_test | P-001 | positive |

## Acceptance Criteria

| ID | Criterion | Related Plan Item | Verification Method |
|----|-----------|-------------------|---------------------|
| AC-001 | All tests pass | T-001, T-002 | automated_test |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-AN010",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:anan010",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create anomaly ledger with unresolved anomaly
cat > "$TEST_DIR/anomaly_ledger.json" <<'EOF'
{
  "ledger_id": "TEST-AN010-LEDGER",
  "plan_id": "TEST-AN010",
  "entries": [
    {
      "entry_id": "ANM-001",
      "timestamp": "2026-06-10T00:00:00Z",
      "phase_id": "phase_1",
      "anomaly_type": "basic_achievement",
      "description": "Test anomaly",
      "severity": "P2",
      "status": "open",
      "related_plan_items": ["T-001"]
    }
  ]
}
EOF

# Create evidence
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:anan010",
    "plan_item_ids": ["T-001"]
  },
  "tests_run": ["integration_test"],
  "tests_skipped": ["performance_test"],
  "changed_files": ["src/test.py"]
}
EOF

# Test: Check anomaly (should BLOCK or FAIL)
echo ""
echo "Test: Check anomaly ledger"

set +e
OUTPUT=$(bash scripts/hmte-anomaly-ledger.sh \
  --ledger "$TEST_DIR/anomaly_ledger.json" \
  --evidence "$TEST_DIR/evidence.json" \
  --plan "$TEST_DIR/test_plan.md" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(escalate|P1|required.*test)"; then
  echo "✅ PASS: Correctly blocked for required_test_basic_achievement_escalates_to_p1"
  RESULT=0
else
  echo "❌ FAIL: Did not block for required_test_basic_achievement_escalates_to_p1"
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
