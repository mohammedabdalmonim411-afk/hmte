#!/usr/bin/env bash
# E014_release_gate_final_check_failure_blocking.sh — Test: Release gate MUST FAIL when final-check fails
#
# This test creates a scenario where hmte-final-check.sh fails
# and verifies the release gate FAILS (does not PASS).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

# Strategy: Create a temporary test environment with a fake final-check that fails,
# but everything else passes. Release gate must FAIL.

mkdir -p "$TEMP_DIR/scripts" "$TEMP_DIR/.phase_control/audits" "$TEMP_DIR/evals/cases"

# Copy the release gate script
cp "$PROJECT_ROOT/scripts/hmte-release-gate.sh" "$TEMP_DIR/scripts/"

# Create a minimal eval that passes
cat > "$TEMP_DIR/scripts/hmte-eval.sh" <<'EVAL'
#!/bin/bash
echo "Fake eval: PASS"
exit 0
EVAL
chmod +x "$TEMP_DIR/scripts/hmte-eval.sh"

# Create a lint that passes
cat > "$TEMP_DIR/scripts/hmte-lint-protocol.sh" <<'LINT'
#!/bin/bash
echo "Fake lint: PASS"
exit 0
LINT
chmod +x "$TEMP_DIR/scripts/hmte-lint-protocol.sh"

# Create a final-check that FAILS
cat > "$TEMP_DIR/scripts/hmte-final-check.sh" <<'FCHECK'
#!/bin/bash
echo "FAIL: session.json missing required fields"
exit 1
FCHECK
chmod +x "$TEMP_DIR/scripts/hmte-final-check.sh"

# Create a dogfood audit pack
echo "# Dogfood Audit Report" > "$TEMP_DIR/.phase_control/audits/dogfood_audit.md"

# Create an external audit receipt
echo '{"status": "PASS"}' > "$TEMP_DIR/.phase_control/external_audit_receipt.json"

# Initialize git repo (clean — no .phase_control in staging)
cd "$TEMP_DIR"
git init > /dev/null 2>&1
git add scripts/ > /dev/null 2>&1
git config user.email "test@test.com" 2>/dev/null || true
git config user.name "Test" 2>/dev/null || true
git commit -m "init" > /dev/null 2>&1

# Run the release gate
cd "$TEMP_DIR"
OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

# Verify: release gate MUST FAIL
if [ "$EXIT_CODE" -eq 0 ]; then
    echo "FAIL: Release gate returned exit 0 (PASS) when final-check failed"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

# Verify: output must NOT contain PASS verdict
if echo "$OUTPUT" | grep -q "VERDICT: PASS"; then
    echo "FAIL: Release gate output contains PASS verdict when final-check failed"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

# Verify: output must contain FAIL verdict
if ! echo "$OUTPUT" | grep -q "VERDICT: FAIL"; then
    echo "FAIL: Release gate output does not contain FAIL verdict when final-check failed"
    echo "Output:"
    echo "$OUTPUT"
    exit 1
fi

echo "PASS: E014 — Release gate correctly FAILS when final-check fails"
exit 0
