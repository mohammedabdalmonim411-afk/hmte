#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 07: Coverage report replaced by core tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check PD005 eval case (already exists)
OUTPUT=$(bash evals/cases/PD005_coverage_report_required_but_replaced_by_core_tests.sh 2>&1) || true
if echo "$OUTPUT" | grep -q "PASS"; then
  echo "✅ PASS: PD005 eval case covers this scenario"
  exit 0
else
  echo "❌ FAIL: PD005 eval case failed"
  exit 1
fi
