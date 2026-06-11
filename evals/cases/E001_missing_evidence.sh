#!/usr/bin/env bash
# E001_missing_evidence.sh — Test: Missing evidence file → phase_gate FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$PROJECT_ROOT/evals/fixtures/invalid_no_evidence"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

# Setup: phases.json + verdict exist, but no evidence / receipt / command log
mkdir -p .phase_control/evidence .phase_control/verdicts .phase_control/logs
cp "$FIXTURE_DIR/phases.json" .phase_control/phases.json
cp "$FIXTURE_DIR/verdict.json" ".phase_control/verdicts/test_phase_attempt_1.json" 2>/dev/null || true

# Copy phase_gate.sh wrapper
mkdir -p scripts
cp "$PROJECT_ROOT/scripts/phase_gate.sh" scripts/

# Set HMTE_SKILL_DIR so phase_gate can find implementation
export HMTE_SKILL_DIR="$PROJECT_ROOT/src/skills/hmte"

# Run phase_gate - should FAIL due to missing evidence
OUTPUT=$(bash scripts/phase_gate.sh test_phase --attempt 1 2>&1) || GATE_EXIT=$?

# Check exit code
if [ "${GATE_EXIT:-0}" -eq 0 ]; then
    echo "FAIL: phase_gate should have failed with missing evidence"
    echo "Output: $OUTPUT"
    exit 1
fi

# Check failure reason contains missing evidence (not path errors)
if echo "$OUTPUT" | grep -qE "evidence.*not found|evidence.*missing|check4.evidence|BLOCKED.*evidence"; then
    echo "PASS: phase_gate correctly failed due to missing evidence"
    exit 0
else
    echo "FAIL: phase_gate failed for wrong reason (not missing evidence)"
    echo "Output: $OUTPUT"
    exit 1
fi
