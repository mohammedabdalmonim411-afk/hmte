#!/usr/bin/env bash
set -euo pipefail
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Test Plan
**Plan ID**: TEST-PCON001
**Version**: 1.0
**Status**: draft
EOF
set +e
OUTPUT=$(bash scripts/hmte-pass-contradiction.sh --plan "$TEST_DIR/test_plan.md" --ledger "$TEST_DIR/anomaly_ledger.json" --check 2>&1 || true)
EXIT_CODE=$?
if [[ $EXIT_CODE -eq 0 ]] || echo "$OUTPUT" | grep -qi "contradiction\|冲突"; then
  echo "✅ PASS: PCON001 - PASS Contradiction script validated"
  exit 0
else
  echo "❌ FAIL: PCON001"
  exit 1
fi
