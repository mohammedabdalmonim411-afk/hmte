#!/usr/bin/env bash
# E004_multi_phase_missing_acceptance_criteria.sh
# Negative case: 第 1 个 phase 缺 acceptance_criteria，第 2 个合法
# Expected: FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Setup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/.phase_control"
cd "$TEMP_DIR"

# Create phases.json with first phase missing acceptance_criteria
cat > .phase_control/phases.json <<'EOF'
{
  "project_name": "E004 Test",
  "phases": [
    {
      "phase_id": "phase_bad",
      "goal": "This phase is missing acceptance_criteria"
    },
    {
      "phase_id": "phase_good",
      "goal": "This phase has acceptance_criteria",
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
    echo "PASS: Validator correctly FAILed (multi-phase with one missing acceptance_criteria)"
    exit 0  # Test passed: validator correctly rejected invalid schema
fi
