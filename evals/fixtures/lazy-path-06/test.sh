#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 06: Leader simplifies plan item"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check PD007 eval case (already exists)
OUTPUT=$(bash evals/cases/PD007_leader_simplifies_plan_item_into_smaller_task.sh 2>&1) || true
if echo "$OUTPUT" | grep -q "PASS"; then
  echo "✅ PASS: PD007 eval case covers this scenario"
  exit 0
else
  echo "❌ FAIL: PD007 eval case failed"
  exit 1
fi
