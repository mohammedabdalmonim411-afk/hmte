#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 04: Release pack 遗漏 failure context"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

OUTPUT=$(bash evals/cases/PCON004_release_pack_missing_failure_context.sh 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "Correctly FAILED for release_pack_missing_failure_context"; then
  echo "✅ PASS: Gate/eval captured release pack missing failure context"
  echo "$OUTPUT" | tail -12
  exit 0
fi

echo "❌ FAIL: Gate/eval did not capture release pack missing failure context"
echo "Exit code: $EXIT_CODE"
echo "$OUTPUT"
exit 1
