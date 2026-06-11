#!/usr/bin/env bash
#
# AN002: skipped_required_test_without_disposition_blocks_gate
#
# Test that gate BLOCKS when required test is skipped without disposition
#

set -euo pipefail

TEST_NAME="AN002_skipped_required_test_without_disposition_blocks_gate"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-AN002
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
  "plan_id": "TEST-AN002",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:anan002",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create anomaly ledger with unresolved anomaly
cat > "$TEST_DIR/anomaly_ledger.json" <<'EOF'
{
  "ledger_id": "TEST-AN002-LEDGER",
  "plan_id": "TEST-AN002",
  "entries": [
    {
      "entry_id": "ANM-001",
      "timestamp": "2026-06-10T00:00:00Z",
      "phase_id": "phase_1",
      "anomaly_type": "skipped_test",
      "description": "Test anomaly",
      "severity": "P1",
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
    "plan_hash": "sha256:anan002",
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

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(skipped.*test.*disposition|disposition.*required|test.*disposition)"; then
  echo "✅ PASS: Correctly blocked for skipped_required_test_without_disposition_blocks_gate"
  RESULT=0
else
  echo "❌ FAIL: Did not block for skipped_required_test_without_disposition_blocks_gate"
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
