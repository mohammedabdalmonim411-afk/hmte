#!/usr/bin/env bash
# VM001_verifier_instruction_missing_audit_plan_ref - Verifier instruction missing audit_plan_ref should fail
# Type: negative
# Expected: FAIL

set -euo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Test Plan
**Plan ID**: TEST-PLAN-VM001
**Version**: 1.0
**Status**: draft
## Scope
| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Feature | P0 | Test |
EOF

# Verifier instruction WITHOUT audit_plan_ref
cat > "$TEST_DIR/verifier_instruction.json" <<'EOF'
{
  "phase_id": "phase_1",
  "goal": "Verify implementation"
}
EOF

set +e
OUTPUT=$(bash scripts/hmte-check-mandate.sh --instruction "$TEST_DIR/verifier_instruction.json" --plan "$TEST_DIR/test_plan.md" 2>&1)
EXIT_CODE=$?
set -e

if echo "$OUTPUT" | grep -qi "audit_plan_ref.*missing\|缺少.*audit_plan_ref" && [[ $EXIT_CODE -ne 0 ]]; then
  echo "✅ PASS: VM001 - Verifier instruction missing audit_plan_ref correctly detected"
  exit 0
else
  echo "❌ FAIL: VM001 - Missing audit_plan_ref was not detected"
  echo "Exit code: $EXIT_CODE"
  echo "Output: $OUTPUT"
  exit 1
fi
