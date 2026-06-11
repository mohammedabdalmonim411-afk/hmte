#!/usr/bin/env bash
# E005_multi_phase_acceptance_criteria_not_array.sh
# Negative case: 第 1 个 phase acceptance_criteria 是字符串，第 2 个是数组
# Expected: FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Setup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/.phase_control"
cd "$TEMP_DIR"

# Create phases.json with first phase having string acceptance_criteria
cat > .phase_control/phases.json <<'EOF'
{
  "project_name": "E005 Test",
  "phases": [
    {
      "phase_id": "phase_bad",
      "goal": "This phase has string acceptance_criteria",
      "acceptance_criteria": "This should be an array"
    },
    {
      "phase_id": "phase_good",
      "goal": "This phase has array acceptance_criteria",
      "acceptance_criteria": ["Valid criterion"]
    }
  ]
}
EOF

# Run validator (should FAIL)
if bash "$PROJECT_ROOT/scripts/hmte-validate-phases.sh" .phase_control/phases.json 2>&1; then
    echo "ERROR: Validator should have FAILed but PASSed"
    exit 1
else
    echo "PASS: Validator correctly FAILed (multi-phase with one non-array acceptance_criteria)"
    exit 0  # Test passed: validator correctly rejected invalid schema
fi
