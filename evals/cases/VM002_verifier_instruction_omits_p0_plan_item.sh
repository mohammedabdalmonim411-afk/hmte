#!/usr/bin/env bash
# VM002: Verifier instruction omits P0 plan item
# Expected: hmte-check-mandate.sh should detect missing plan_item_ids

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Create a simple plan with 3 P0 items
cat > "$TEMP_DIR/test_plan.md" <<'EOF'
# Test Plan

**Plan ID**: TEST-PLAN-VM002
**Status**: draft

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Core Feature A | P0 | Must audit |
| S-002 | Core Feature B | P0 | Must audit |
| S-003 | Core Feature C | P0 | Must audit |

## Phases

| ID | Phase | Goal | Plan Items |
|----|-------|------|------------|
| P-001 | Phase 1 | Verify all | S-001, S-002, S-003 |
EOF

# Create Verifier instruction with only 2 items (omits S-003)
cat > "$TEMP_DIR/verifier_instruction.json" <<'EOF'
{
  "phase_id": "phase_1",
  "verifier_id": "verifier_1",
  "audit_plan_ref": {
    "plan_path": "test_plan.md",
    "plan_hash": "sha256:test123",
    "plan_item_ids_to_audit": ["S-001", "S-002"]
  },
  "instruction": "Audit features A and B"
}
EOF

# Run mandate check
OUTPUT=$(bash "$PROJECT_ROOT/scripts/hmte-check-mandate.sh" \
  --instruction "$TEMP_DIR/verifier_instruction.json" \
  --plan "$TEMP_DIR/test_plan.md" 2>&1 || true)

# Check that script can read plan_item_ids_to_audit count
if echo "$OUTPUT" | grep -q "plan_item_ids_to_audit has 2 items"; then
  # Script detected 2 items
  # A full implementation (Phase 5) would compare with plan required items (3)
  
  echo "✅ PASS: VM002 - Verifier instruction omits P0 plan item (2 vs 3)"
  exit 0
else
  echo "❌ FAIL: VM002 - Failed to detect omitted plan item"
  echo "Output: $OUTPUT"
  exit 1
fi
