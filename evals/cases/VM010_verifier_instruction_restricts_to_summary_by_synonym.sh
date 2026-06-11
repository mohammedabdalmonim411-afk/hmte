#!/usr/bin/env bash
#
# VM010: verifier_instruction_restricts_to_summary_by_synonym
#
# Test that gate FAILS when Verifier instruction uses synonym to restrict to summary
#

set -euo pipefail

TEST_NAME="VM010_verifier_instruction_restricts_to_summary_by_synonym"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-VM010
**Version**: 1.0
**Status**: locked

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Feature A | P0 | Core feature |
| S-002 | Feature B | P0 | Required feature |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | test_a | P-001 | positive |
| T-002 | test_b | P-001 | positive |
EOF

# Create plan lock
cat > "$TEST_DIR/plan_lock.json" <<'EOF'
{
  "plan_id": "TEST-VM010",
  "plan_path": "test_plan.md",
  "plan_hash": "sha256:vmvm010",
  "approved_by": "human",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create Verifier instruction with issue: uses 'quick review' / 'spot check' synonym for summary-only
cat > "$TEST_DIR/verifier_instruction.json" <<'EOF'
{
  "audit_plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:vmvm010",
    "plan_item_ids_to_audit": ["S-001"],
    "forbidden_shortcuts": ["skip command log"]
  }
}
EOF

# Create evidence
cat > "$TEST_DIR/evidence.json" <<'EOF'
{
  "plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:vmvm010",
    "plan_item_ids": ["S-001", "S-002"]
  },
  "changed_files": ["src/feature_a.py", "src/feature_b.py"]
}
EOF

# Test: Check mandate (should FAIL)
echo ""
echo "Test: Check Verifier mandate"

set +e
OUTPUT=$(bash scripts/hmte-check-mandate.sh \
  --instruction "$TEST_DIR/verifier_instruction.json" \
  --evidence "$TEST_DIR/evidence.json" \
  --plan "$TEST_DIR/test_plan.md" \
  --plan-lock "$TEST_DIR/plan_lock.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -qE "(quick.*review|spot.*check|forbidden.*shortcut)"; then
  echo "✅ PASS: Correctly FAILED for verifier_instruction_restricts_to_summary_by_synonym"
  RESULT=0
else
  echo "❌ FAIL: Did not FAIL for verifier_instruction_restricts_to_summary_by_synonym"
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
