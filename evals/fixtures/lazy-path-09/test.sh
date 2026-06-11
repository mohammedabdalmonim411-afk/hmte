#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 09: Verifier instruction omits plan item"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check VM002 or VM007 eval case (already exists)
if bash evals/cases/VM002_verifier_instruction_omits_p0_plan_item.sh 2>&1 | grep -q "PASS"; then
  echo "✅ PASS: VM002 eval case covers this scenario"
  exit 0
else
  echo "❌ FAIL: VM002 eval case failed"
  exit 1
fi
