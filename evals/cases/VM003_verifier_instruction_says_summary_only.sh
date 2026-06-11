#!/usr/bin/env bash
# VM003: Verifier instruction says "summary only"
# Expected: hmte-check-mandate.sh should detect forbidden shortcut

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Create a simple plan
cat > "$TEMP_DIR/test_plan.md" <<'EOF'
# Test Plan

**Plan ID**: TEST-PLAN-VM003
**Status**: draft

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Feature X | P0 | Must audit |

## Phases

| ID | Phase | Goal | Plan Items |
|----|-------|------|------------|
| P-001 | Phase 1 | Verify | S-001 |
EOF

# Create Verifier instruction with forbidden shortcut
cat > "$TEMP_DIR/verifier_instruction.json" <<'EOF'
{
  "phase_id": "phase_1",
  "verifier_id": "verifier_1",
  "audit_plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:test456",
    "plan_item_ids_to_audit": ["S-001"]
  },
  "instruction": "Perform summary-only review of feature X"
}
EOF

# Run mandate check
OUTPUT=$(bash "$PROJECT_ROOT/scripts/hmte-check-mandate.sh" \
  --instruction "$TEMP_DIR/verifier_instruction.json" \
  --plan "$TEMP_DIR/test_plan.md" 2>&1 || true)

# Check that script detects forbidden shortcut
if echo "$OUTPUT" | grep -iq "forbidden.*shortcut\|summary.only"; then
  echo "✅ PASS: VM003 - Verifier instruction forbidden shortcut detected"
  exit 0
else
  echo "❌ FAIL: VM003 - Failed to detect forbidden shortcut"
  echo "Output: $OUTPUT"
  exit 1
fi
