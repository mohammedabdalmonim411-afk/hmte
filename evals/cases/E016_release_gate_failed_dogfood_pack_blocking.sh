#!/usr/bin/env bash
# E016: Release gate must block when dogfood audit pack exists but has FAIL result
#
# This tests the fix for the P0 bug where release gate only checked
# whether a dogfood report file existed, not whether it actually passed.
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

# Create a FAILED dogfood audit pack
cat > "$TEMP_DIR/.phase_control/audits/audit_dogfood_20260606.md" <<'REPORT'
# Dogfood Audit Report

## Summary

- **Checks**: 3/5 passed
- **Failed**: 2

**Result: FAIL** — 2 check(s) failed
REPORT

# Create an external audit receipt
touch "$TEMP_DIR/.phase_control/external_audit_receipt.json"

# Initialize git repo (clean staging)
cd "$TEMP_DIR"
git init -q

# Run release gate
OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

# Verify: release gate must FAIL
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "FAIL: Release gate returned exit 0 (PASS) when dogfood report had FAIL result"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

# Verify: output must NOT contain PASS verdict
if echo "$OUTPUT" | grep -q "VERDICT: PASS"; then
    echo "FAIL: Release gate output contains PASS verdict when dogfood report had FAIL result"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

# Verify: output must mention dogfood failure
if ! echo "$OUTPUT" | grep -qi "dogfood.*did not pass\|dogfood.*fail"; then
    echo "FAIL: Release gate output does not mention dogfood failure"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: E016 — Release gate correctly blocks failed dogfood audit pack"
exit 0
