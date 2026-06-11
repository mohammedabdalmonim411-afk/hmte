#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 11: Final summary hides partial pass"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check PCON003 eval case (already exists)
OUTPUT=$(bash evals/cases/PCON003_44_44_pass_hides_23_26_history.sh 2>&1) || true
if echo "$OUTPUT" | grep -q "PASS"; then
  echo "✅ PASS: PCON003 eval case covers this scenario"
  exit 0
else
  echo "❌ FAIL: PCON003 eval case failed"
  exit 1
fi
