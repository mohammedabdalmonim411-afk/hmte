#!/usr/bin/env bash
# E007_multi_phase_parallel_worker_missing_fields.sh
# Negative case: parallel_safe phase 中一个 worker 缺 forbidden_paths
# Expected: FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Setup
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/.phase_control"
cd "$TEMP_DIR"

# Create phases.json with one worker missing forbidden_paths
cat > .phase_control/phases.json <<'EOF'
{
  "project_name": "E007 Test",
  "phases": [
    {
      "phase_id": "phase_parallel",
      "goal": "Parallel phase with one bad worker",
      "acceptance_criteria": ["Criterion"],
      "execution_mode": "parallel_safe",
      "parallel_workers": [
        {
          "worker_id": "worker_bad",
          "scope": "Some scope"
        },
        {
          "worker_id": "worker_good",
          "scope": "Some scope",
          "forbidden_paths": ["path"]
        }
      ]
    }
  ]
}
EOF

# Run validator (should FAIL)
if bash "$PROJECT_ROOT/scripts/hmte-validate-phases.sh" .phase_control/phases.json 2>&1; then
    echo "ERROR: Validator should have FAILed but PASSed"
    exit 1
else
    echo "PASS: Validator correctly FAILed (parallel_safe worker missing forbidden_paths)"
    exit 0  # Test passed: validator correctly rejected invalid schema
fi
