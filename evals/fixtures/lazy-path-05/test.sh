#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 05: Final summary 洗白历史 timeout"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

OUTPUT=$(bash evals/cases/PCON005_final_summary_washes_failed_history.sh 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "Correctly FAILED for final_summary_washes_failed_history"; then
  echo "✅ PASS: Gate/eval captured final summary washing failed history"
  echo "$OUTPUT" | tail -12
  exit 0
fi

echo "❌ FAIL: Gate/eval did not capture final summary washing failed history"
echo "Exit code: $EXIT_CODE"
echo "$OUTPUT"
exit 1
