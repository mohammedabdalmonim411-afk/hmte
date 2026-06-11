#!/usr/bin/env bash
# E006_multi_phase_invalid_execution_mode.sh
# Negative case: 第 1 个 phase execution_mode 非法，第 2 个合法
# Expected: FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Setup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/.phase_control"
cd "$TEMP_DIR"

# Create phases.json with first phase having invalid execution_mode
cat > .phase_control/phases.json <<'EOF'
{
  "project_name": "E006 Test",
  "phases": [
    {
      "phase_id": "phase_bad",
      "goal": "This phase has invalid execution_mode",
      "acceptance_criteria": ["Criterion"],
      "execution_mode": "bad_mode"
    },
    {
      "phase_id": "phase_good",
      "goal": "This phase has valid execution_mode",
      "acceptance_criteria": ["Criterion"],
      "execution_mode": "sequential"
    }
  ]
}
EOF

# Run validator (should FAIL)
if bash "$PROJECT_ROOT/scripts/hmte-validate-phases.sh" .phase_control/phases.json 2>&1; then
    echo "ERROR: Validator should have FAILed but PASSed"
    exit 1
else
    echo "PASS: Validator correctly FAILed (multi-phase with one invalid execution_mode)"
    exit 0  # Test passed: validator correctly rejected invalid schema
fi
