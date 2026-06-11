#!/usr/bin/env bash
# PD001_worker_instruction_missing_plan_ref - Plan-to-Delegation: Worker instruction missing plan_ref should fail
# Type: negative
# Expected: FAIL

set -euo pipefail

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create a test plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Test Plan

**Plan ID**: TEST-PLAN-PD001
**Version**: 1.0
**Status**: draft

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Implement Feature | P0 | Core feature |
EOF

# Create Worker instruction WITHOUT plan_ref
cat > "$TEST_DIR/instruction.json" <<'EOF'
{
  "phase_id": "phase_1",
  "goal": "Implement core feature",
  "allowed_files": ["src/"],
  "forbidden_files": [".phase_control/"]
}
EOF

# Run fidelity check (should fail)
set +e
OUTPUT=$(bash scripts/hmte-check-fidelity.sh --instruction "$TEST_DIR/instruction.json" --plan "$TEST_DIR/test_plan.md" 2>&1)
EXIT_CODE=$?
set -e

if echo "$OUTPUT" | grep -qi "plan_ref.*missing\|缺少.*plan_ref" && [[ $EXIT_CODE -ne 0 ]]; then
  echo "✅ PASS: PD001 - Worker instruction missing plan_ref correctly detected"
  exit 0
else
  echo "❌ FAIL: PD001 - Worker instruction missing plan_ref was not detected"
  echo "Exit code: $EXIT_CODE"
  echo "Output: $OUTPUT"
  exit 1
fi
