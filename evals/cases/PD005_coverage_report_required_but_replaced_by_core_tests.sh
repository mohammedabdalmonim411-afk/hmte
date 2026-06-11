#!/usr/bin/env bash
#
# PD005: coverage_report_required_but_replaced_by_core_tests
#
# Test that gate FAILS when coverage report is required but only core tests are provided
#

set -euo pipefail

TEST_NAME="PD005_coverage_report_required_but_replaced_by_core_tests"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan requiring coverage report
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-PD005
**Version**: 1.0
**Status**: locked

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | core_tests | P-001 | positive |

## Acceptance Criteria

| ID | Criterion | Related Plan Item |
|----|-----------|-------------------|
| AC-001 | Coverage report >= 80% | T-001 |

## Required Artifacts

| ID | Artifact | Description |
|----|----------|-------------|
| ART-001 | coverage_report.html | Full coverage report |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-PD005",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:def456",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create evidence without coverage report (only core tests)
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:def456",
    "plan_item_ids": ["T-001"]
  },
  "tests_run": ["core_tests"],
  "changed_files": ["src/core.py"],
  "summary": "Core tests passed, coverage looks good"
}
EOF

# Test: Check fidelity (should FAIL - missing required artifact)
echo ""
echo "Test: Check fidelity for missing coverage report"

set +e
OUTPUT=$(bash scripts/hmte-check-fidelity.sh \
  --evidence "$TEST_DIR/evidence.json" \
  --plan "$TEST_DIR/test_plan.md" \
  --plan-lock "$TEST_DIR/plan_lock.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(required.*artifact|coverage.*report|missing.*artifact)"; then
  echo "✅ PASS: Correctly FAILED when coverage report missing"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL when coverage report missing"
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
