#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 02: Worker 只做容易部分"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check if evidence has fidelity issues (missing fields, hash mismatch)
OUTPUT=$(bash scripts/hmte-check-fidelity.sh \
  --evidence "$SCRIPT_DIR/fake_evidence.json" \
  --plan "$SCRIPT_DIR/fake_plan.md" 2>&1 || true)

# Fidelity check should detect evidence issues (missing evidence_by_plan_item, hash mismatch)
if echo "$OUTPUT" | grep -qE "FAILED|missing.*plan|hash.*mismatch"; then
  echo "✅ PASS: Fidelity check detected evidence gaps ($(echo "$OUTPUT" | grep -c '✗') errors)"
  exit 0
else
  echo "❌ FAIL: Fidelity check did not detect issues"
  echo "$OUTPUT"
  exit 1
fi
