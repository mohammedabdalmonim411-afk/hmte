#!/usr/bin/env bash
# E010_release_gate_missing_dogfood.sh — Test: Release gate reports correctly when dogfood pack missing
#
# Verifies that missing dogfood audit pack is detected and reported.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

# Create a minimal project structure
mkdir -p scripts .phase_control

# Copy the release gate script
cp "$PROJECT_ROOT/scripts/hmte-release-gate.sh" "$TEMP_DIR/scripts/"

# Create scripts that pass
cat > scripts/hmte-eval.sh <<'EVAL'
#!/bin/bash
exit 0
EVAL
chmod +x scripts/hmte-eval.sh

cat > scripts/hmte-lint-protocol.sh <<'LINT'
#!/bin/bash
exit 0
LINT
chmod +x scripts/hmte-lint-protocol.sh

cat > scripts/hmte-final-check.sh <<'FCHECK'
#!/bin/bash
exit 0
FCHECK
chmod +x scripts/hmte-final-check.sh

# Initialize git repo (clean staging)
git init > /dev/null 2>&1

# No dogfood audit pack exists

# Run release gate
OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1) || GATE_EXIT=$?

# The release gate should FAIL (P1: missing dogfood) or PENDING
# It should NOT pass when dogfood is missing
if [ "${GATE_EXIT:-0}" -eq 0 ]; then
    echo "FAIL: Release gate should not PASS when dogfood audit pack is missing"
    echo "Output: $OUTPUT"
    exit 1
fi

# Verify the output mentions dogfood
if echo "$OUTPUT" | grep -qi "dogfood"; then
    echo "PASS: Release gate correctly detected missing dogfood audit pack"
    exit 0
else
    echo "FAIL: Release gate did not mention dogfood in output"
    echo "Output: $OUTPUT"
    exit 1
fi
