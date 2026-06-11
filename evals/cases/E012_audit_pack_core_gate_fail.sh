#!/usr/bin/env bash
# E012_audit_pack_core_gate_fail.sh — Test: Audit pack core mode detects gate failure
#
# Verifies that audit pack --mode core detects when gate checks fail.

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
mkdir -p scripts .phase_control/audits

# Copy the audit pack script
cp "$PROJECT_ROOT/scripts/hmte-audit-pack.sh" "$TEMP_DIR/scripts/"

# Create a FAILING eval harness (simulates gate failure)
cat > scripts/hmte-eval.sh <<'EVAL'
#!/bin/bash
echo "FAIL: simulated eval failure" >&2
exit 1
EVAL
chmod +x scripts/hmte-eval.sh

# Create other scripts that pass
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

# Create minimal required files for core mode
touch scripts/phase_gate.sh
touch scripts/hmte-release-gate.sh
mkdir -p docs
echo "# Protocol" > docs/HTE_PROTOCOL.md
mkdir -p src/skills/hmte
echo "# Skill" > src/skills/hmte/SKILL.md

# Run audit pack in core mode — should detect the failing eval
OUTPUT=$(bash scripts/hmte-audit-pack.sh --mode core --project-root "$TEMP_DIR" 2>&1) || PACK_EXIT=$?

if [ "${PACK_EXIT:-0}" -ne 1 ]; then
    echo "FAIL: Audit pack core mode should exit 1 when gate checks fail, got ${PACK_EXIT:-0}"
    echo "Output: $OUTPUT"
    exit 1
fi

# Verify the output mentions the failure
if echo "$OUTPUT" | grep -qiE "FAIL|failed|Eval Harness"; then
    echo "PASS: Audit pack core mode correctly detected gate failure"
    exit 0
else
    echo "FAIL: Audit pack core mode did not report the gate failure"
    echo "Output: $OUTPUT"
    exit 1
fi
