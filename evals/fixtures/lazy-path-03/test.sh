#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 03: Verifier 礼貌型 PASS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

OUTPUT=$(bash scripts/hmte-check-mandate.sh \
  --verdict "$SCRIPT_DIR/fake_verdict.json" \
  --plan "$SCRIPT_DIR/fake_plan.md" 2>&1 || true)

if echo "$OUTPUT" | grep -qi "missing.*audit_plan_ref\|missing.*zero_finding"; then
  echo "✅ PASS: Mandate check detected missing audit_plan_ref or zero_finding justification"
  exit 0
else
  echo "❌ FAIL: Mandate check did not detect issues"
  echo "$OUTPUT"
  exit 1
fi
