#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Lazy-Path Case 10: Verifier limits review to summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd "$PROJECT_ROOT"

# Check VM003 or VM008 eval case (already exists)
if bash evals/cases/VM003_verifier_instruction_says_summary_only.sh 2>&1 | grep -q "PASS"; then
  echo "✅ PASS: VM003 eval case covers this scenario"
  exit 0
else
  echo "❌ FAIL: VM003 eval case failed"
  exit 1
fi
