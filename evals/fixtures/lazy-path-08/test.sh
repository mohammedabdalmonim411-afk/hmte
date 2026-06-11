#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 08: Integration tests skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check PD004 eval case (already exists)
OUTPUT=$(bash evals/cases/PD004_integration_tests_skipped_without_amendment.sh 2>&1) || true
if echo "$OUTPUT" | grep -q "PASS"; then
  echo "✅ PASS: PD004 eval case covers this scenario"
  exit 0
else
  echo "❌ FAIL: PD004 eval case failed"
  exit 1
fi
