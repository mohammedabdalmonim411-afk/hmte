#!/usr/bin/env bash
# E008_release_gate_p0_blocking.sh — Test: Release gate MUST FAIL when P0 > 0
#
# This test creates a scenario where a P0 issue exists
# (staged .phase_control/ files in git) and verifies the release gate FAILS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
    # Clean up any git staging we might have done
    cd "$PROJECT_ROOT"
    git reset HEAD .phase_control/ > /dev/null 2>&1 || true
}
trap cleanup EXIT

cd "$PROJECT_ROOT"

# Strategy: We test the release gate's P0 detection by checking its logic.
# Since we can't easily create a real P0 without corrupting the repo,
# we test the release gate script's P0 counting logic directly.

# Create a temporary test environment with a fake project structure
mkdir -p "$TEMP_DIR/scripts" "$TEMP_DIR/.phase_control" "$TEMP_DIR/evals/cases"

# Copy the release gate script
cp "$PROJECT_ROOT/scripts/hmte-release-gate.sh" "$TEMP_DIR/scripts/"

# Create a minimal eval that passes
cat > "$TEMP_DIR/scripts/hmte-eval.sh" <<'EVAL'
#!/bin/bash
echo "Fake eval: PASS"
exit 0
EVAL
chmod +x "$TEMP_DIR/scripts/hmte-eval.sh"

# Create a minimal lint that passes
cat > "$TEMP_DIR/scripts/hmte-lint-protocol.sh" <<'LINT'
#!/bin/bash
echo "Fake lint: PASS"
exit 0
LINT
chmod +x "$TEMP_DIR/scripts/hmte-lint-protocol.sh"

# Create a minimal final-check that passes
cat > "$TEMP_DIR/scripts/hmte-final-check.sh" <<'FCHECK'
#!/bin/bash
echo "Fake final-check: PASS"
exit 0
FCHECK
chmod +x "$TEMP_DIR/scripts/hmte-final-check.sh"

# Initialize git repo and stage .phase_control/ files (P0 violation)
cd "$TEMP_DIR"
git init > /dev/null 2>&1
echo "test" > .phase_control/test.json
git add .phase_control/test.json > /dev/null 2>&1

# Run release gate — should FAIL due to P0 (.phase_control in git staging)
OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1) || GATE_EXIT=$?

if [ "${GATE_EXIT:-0}" -eq 1 ]; then
    # Check that the output mentions P0
    if echo "$OUTPUT" | grep -qi "P0"; then
        echo "PASS: Release gate correctly failed with P0 issue"
        exit 0
    else
        echo "FAIL: Release gate failed but didn't mention P0"
        echo "Output: $OUTPUT"
        exit 1
    fi
else
    echo "FAIL: Release gate should have failed with P0 > 0"
    echo "Exit code: ${GATE_EXIT:-0}"
    echo "Output: $OUTPUT"
    exit 1
fi
