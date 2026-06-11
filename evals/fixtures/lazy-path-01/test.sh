#!/usr/bin/env bash
#
# Lazy-Path Case 01 Test: Leader 阉割计划
#
# Expected: hmte-check-fidelity.sh FAIL (missing plan_ref)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 01: Leader 阉割计划"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Run fidelity check (expect it to fail)
echo "Running: bash scripts/hmte-check-fidelity.sh --instruction ... --plan ..."

if bash scripts/hmte-check-fidelity.sh \
  --instruction "$SCRIPT_DIR/fake_worker_instruction.json" \
  --plan "$SCRIPT_DIR/fake_plan.md" 2>&1; then
  echo "❌ FAIL: Fidelity check passed when it should have failed"
  exit 1
else
  # Check if the failure is due to missing plan_ref
  OUTPUT=$(bash scripts/hmte-check-fidelity.sh \
    --instruction "$SCRIPT_DIR/fake_worker_instruction.json" \
    --plan "$SCRIPT_DIR/fake_plan.md" 2>&1 || true)
  
  if echo "$OUTPUT" | grep -q "missing plan_ref"; then
    echo "✅ PASS: Fidelity check detected missing plan_ref"
    exit 0
  else
    echo "❌ FAIL: Fidelity check failed but not due to missing plan_ref"
    echo "$OUTPUT"
    exit 1
  fi
fi
