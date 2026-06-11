#!/usr/bin/env bash
#
# PCON009: final_report_structured_pass_conflicts_with_anomaly_ledger
#
# Test that release_gate FAILS when final_report structured fields conflict with anomaly ledger
#

set -euo pipefail

TEST_NAME="PCON009_final_report_structured_pass_conflicts_with_anomaly_ledger"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-PCON009
**Version**: 1.0
**Status**: locked

## Release Conditions

| ID | Condition | Verification |
|----|-----------|--------------|
| RC-001 | All tests pass | automated |
| RC-002 | No unresolved anomalies | gate_check |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-PCON009",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:pconpcon009",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create anomaly ledger with contradiction: anomaly ledger shows skipped tests
cat > "$TEST_DIR/anomaly_ledger.json" <<'EOF'
{
  "ledger_id": "TEST-PCON009-LEDGER",
  "plan_id": "TEST-PCON009",
  "entries": [
    {
      "entry_id": "ANM-001",
      "timestamp": "2026-06-10T00:00:00Z",
      "phase_id": "phase_7",
      "anomaly_type": "partial_test_pass",
      "description": "23/26 tests passed, 3 failed",
      "severity": "P1",
      "status": "open",
      "related_plan_items": ["T-007"]
    }
  ]
}
EOF

# Create final report claiming: tests_failed: 0, tests_skipped: 0
cat > "$TEST_DIR/final_report.json" <<'EOF'
{
  "tests_total": 44,
  "tests_passed": 44,
  "tests_failed": 0,
  "tests_skipped": 0,
  "tests_timed_out": 0,
  "open_anomalies": 0,
  "accepted_risks": 0,
  "closed_anomalies": 0,
  "production_ready": true
}
EOF

# Test: Check contradiction (should FAIL)
echo ""
echo "Test: Check PASS contradiction"

set +e
OUTPUT=$(bash scripts/hmte-pass-contradiction.sh \
  --plan "$TEST_DIR/test_plan.md" \
  --anomaly-ledger "$TEST_DIR/anomaly_ledger.json" \
  --final-report "$TEST_DIR/final_report.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(structured.*conflict|tests_failed|tests_skipped|contradiction)"; then
  echo "✅ PASS: Correctly FAILED for final_report_structured_pass_conflicts_with_anomaly_ledger"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL for final_report_structured_pass_conflicts_with_anomaly_ledger"
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
