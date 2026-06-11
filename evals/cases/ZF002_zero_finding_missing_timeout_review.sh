#!/usr/bin/env bash
#
# ZF002: zero_finding_missing_timeout_review
#
# Test that gate FAILS when zero-finding justification omits timeout review
#

set -euo pipefail

TEST_NAME="ZF002_zero_finding_missing_timeout_review"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-ZF002
**Version**: 1.0
**Status**: locked

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Feature A | P0 | Core feature |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | test_feature | P-001 | positive |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-ZF002",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:zfzf002",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create verdict with issue: checked_anomalies is empty but anomaly ledger has timeout
cat > "$TEST_DIR/verdict.json" <<'EOF'
{
  "verdict": "PASS",
  "audit_plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:zfzf002",
    "plan_item_ids_to_audit": ["S-001"]
  },
  "zero_finding_justification": {
    "checked_plan_items": ["S-001"],
    "checked_files": [],
    "checked_command_logs": [],
    "checked_tests": [],
    "checked_anomalies": [],
    "why_no_p0": "All good",
    "why_no_p1": "Looks fine"
  }
}
EOF

# Create anomaly ledger (for ZF002)
cat > "$TEST_DIR/anomaly_ledger.json" <<'EOF'
{
  "ledger_id": "TEST-ZF002-LEDGER",
  "plan_id": "TEST-ZF002",
  "entries": [
    {
      "entry_id": "ANM-001",
      "timestamp": "2026-06-10T00:00:00Z",
      "phase_id": "phase_1",
      "anomaly_type": "timeout",
      "description": "Worker timeout after 300s",
      "severity": "P1",
      "status": "open"
    }
  ]
}
EOF

# Test: Check zero-finding justification (should FAIL or PENDING)
echo ""
echo "Test: Check zero-finding justification"

set +e
OUTPUT=$(bash scripts/hmte-check-mandate.sh \
  --verdict "$TEST_DIR/verdict.json" \
  --plan "$TEST_DIR/test_plan.md" \
  --anomaly-ledger "$TEST_DIR/anomaly_ledger.json" \
  --check-zero-finding 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(timeout.*review|checked.*anomalies|anomaly.*missing)"; then
  echo "✅ PASS: Correctly identified issue for zero_finding_missing_timeout_review"
  RESULT=0
else
  echo "❌ FAIL: Did not identify issue for zero_finding_missing_timeout_review"
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
