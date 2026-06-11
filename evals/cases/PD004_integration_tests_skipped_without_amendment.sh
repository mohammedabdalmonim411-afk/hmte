#!/usr/bin/env bash
#
# PD004: integration_tests_skipped_without_amendment
#
# Test that gate BLOCKS when integration tests are skipped without plan amendment
#

set -euo pipefail

TEST_NAME="PD004_integration_tests_skipped_without_amendment"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan with required integration tests
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-PD004
**Version**: 1.0
**Status**: locked

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | unit_tests | P-001 | positive |
| T-002 | integration_tests | P-001 | positive |

## Acceptance Criteria

| ID | Criterion | Related Plan Item |
|----|-----------|-------------------|
| AC-001 | All integration tests pass | T-002 |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-PD004",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:abc123",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create Worker instruction that references plan but evidence skips integration tests
cat > "$TEST_DIR/worker_instruction.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:abc123",
    "plan_item_ids": ["T-001", "T-002"],
    "required_tests": ["T-001", "T-002"]
  }
}
EOF

# Create evidence that only ran unit tests (skipped integration tests)
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:abc123",
    "plan_item_ids": ["T-001"]
  },
  "tests_run": ["unit_tests"],
  "tests_skipped": ["integration_tests"],
  "changed_files": ["src/test.py"]
}
EOF

# Test: Check fidelity (should BLOCK - integration tests skipped without amendment)
echo ""
echo "Test: Check fidelity for skipped integration tests"

set +e
OUTPUT=$(bash scripts/hmte-check-fidelity.sh \
  --instruction "$TEST_DIR/worker_instruction.json" \
  --evidence "$TEST_DIR/evidence.json" \
  --plan "$TEST_DIR/test_plan.md" \
  --plan-lock "$TEST_DIR/plan_lock.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(required test.*missing|integration.*skipped|test.*not.*executed)"; then
  echo "✅ PASS: Correctly BLOCKED when integration tests skipped without amendment"
  RESULT=0
else
  echo "❌ FAIL: Did not BLOCK when integration tests skipped"
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
