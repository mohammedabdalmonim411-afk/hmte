#!/usr/bin/env bash
# E009_release_gate_p1_blocking.sh — Test: Release gate MUST FAIL when P1 > 0
#
# This test verifies that the release gate fails when P1 issues exist
# (specifically, missing dogfood audit pack).

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

# No dogfood audit pack exists — this should be a P1 issue
# .phase_control/audits/ directory doesn't exist or has no dogfood files

# Run release gate — should FAIL due to P1 (missing dogfood audit pack)
OUTPUT=$(bash scripts/hmte-release-gate.sh --project-root "$TEMP_DIR" 2>&1) || GATE_EXIT=$?

if [ "${GATE_EXIT:-0}" -eq 1 ]; then
    # Check that the output mentions P1 or dogfood
    if echo "$OUTPUT" | grep -qiE "P1|dogfood"; then
        echo "PASS: Release gate correctly failed with P1 issue (missing dogfood)"
        exit 0
    else
        echo "FAIL: Release gate failed but didn't mention P1 or dogfood"
        echo "Output: $OUTPUT"
        exit 1
    fi
else
    echo "FAIL: Release gate should have failed with P1 > 0 (missing dogfood)"
    echo "Exit code: ${GATE_EXIT:-0}"
    echo "Output: $OUTPUT"
    exit 1
fi
