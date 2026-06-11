#!/usr/bin/env bash
# E015: Release gate must block when a .tar.gz file is staged in git
#
# This tests the fix for the P0 bug where `grep "*.tar.gz"` (regex)
# failed to match actual tar.gz filenames in git staging.
# The fix uses `case` with glob matching instead.
#
# Expected: release gate FAIL (exit non-0), output must NOT contain PASS verdict

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Create a temporary test environment
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Copy the project structure
mkdir -p "$TEMP_DIR/scripts"
mkdir -p "$TEMP_DIR/.phase_control/audits"
mkdir -p "$TEMP_DIR/evals/cases"

# Copy release gate script
cp "$PROJECT_ROOT/scripts/hmte-release-gate.sh" "$TEMP_DIR/scripts/"

# Create a passing eval script
cat > "$TEMP_DIR/scripts/hmte-eval.sh" <<'EVAL'
#!/bin/bash
echo "All eval cases passed"
exit 0
EVAL
chmod +x "$TEMP_DIR/scripts/hmte-eval.sh"

# Create a passing lint script
cat > "$TEMP_DIR/scripts/hmte-lint-protocol.sh" <<'LINT'
#!/bin/bash
exit 0
LINT
chmod +x "$TEMP_DIR/scripts/hmte-lint-protocol.sh"

# Create a passing final-check script
cat > "$TEMP_DIR/scripts/hmte-final-check.sh" <<'FCHECK'
#!/bin/bash
exit 0
FCHECK
chmod +x "$TEMP_DIR/scripts/hmte-final-check.sh"

# Create a dogfood audit pack
touch "$TEMP_DIR/.phase_control/audits/audit_dogfood_20260606.md"

# Create a fake tar.gz file and stage it in git
cd "$TEMP_DIR"
git init -q
echo "test content" > hmte-pack-test.tar.gz
git add -f hmte-pack-test.tar.gz

# Run release gate
OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

# Verify: release gate must FAIL
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "FAIL: Release gate returned exit 0 (PASS) when .tar.gz was staged"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

# Verify: output must NOT contain PASS verdict
if echo "$OUTPUT" | grep -q "VERDICT: PASS"; then
    echo "FAIL: Release gate output contains PASS verdict when .tar.gz was staged"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

# Verify: output must mention sensitive files
if ! echo "$OUTPUT" | grep -qi "sensitive"; then
    echo "FAIL: Release gate output does not mention sensitive files"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: E015 — Release gate correctly blocks staged .tar.gz files"
exit 0
