#!/usr/bin/env bash
#
# PD008: integration_tests_skipped_with_fake_amendment
#
# Test that gate FAILS when integration tests skipped with fabricated amendment
#

set -euo pipefail

TEST_NAME="PD008_integration_tests_skipped_with_fake_amendment"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-PD008
**Version**: 1.0
**Status**: locked

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| T-002 | integration_tests | P-001 | positive |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | test_1 | P-001 | positive |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-PD008",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:testpd008",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create evidence with issue: claims amendment but amendment not found
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:testpd008",
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

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(amendment.*not.*found|invalid.*amendment|fake.*amendment)"; then
  echo "✅ PASS: Correctly FAILED for integration_tests_skipped_with_fake_amendment"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL for integration_tests_skipped_with_fake_amendment"
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
