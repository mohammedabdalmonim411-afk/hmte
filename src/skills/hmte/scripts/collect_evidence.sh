#!/bin/bash
# Collect evidence for a phase execution with input validation

set -e

PHASE_ID="$1"
ATTEMPT="$2"
EVIDENCE_DIR=".phase_control/evidence"

# Validate inputs
if [ -z "$PHASE_ID" ] || [ -z "$ATTEMPT" ]; then
    echo "Usage: collect_evidence.sh <phase_id> <attempt>" >&2
    exit 1
fi

# Validate PHASE_ID: only alphanumeric, underscore, hyphen
if ! echo "$PHASE_ID" | grep -qE '^[a-zA-Z0-9_-]+$'; then
    echo "Error: Invalid phase_id '$PHASE_ID'. Only alphanumeric, underscore, and hyphen allowed." >&2
    exit 1
fi

# Validate ATTEMPT: must be positive integer
if ! echo "$ATTEMPT" | grep -qE '^[0-9]+$' || [ "$ATTEMPT" -lt 1 ]; then
    echo "Error: Invalid attempt '$ATTEMPT'. Must be a positive integer." >&2
    exit 1
fi

echo "Collecting evidence for $PHASE_ID (attempt $ATTEMPT)..."

# Create evidence directory if not exists
mkdir -p "$EVIDENCE_DIR"

EVIDENCE_FILE="$EVIDENCE_DIR/${PHASE_ID}_attempt_${ATTEMPT}.json"

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Export variables for Python script
export PHASE_ID ATTEMPT TIMESTAMP EVIDENCE_FILE

# Use Python to generate JSON safely (no injection risk)
python << 'PYTHON_EOF'
import json
import sys
import os

phase_id = os.environ.get('PHASE_ID', '')
attempt = int(os.environ.get('ATTEMPT', '0'))
timestamp = os.environ.get('TIMESTAMP', '')
evidence_file = os.environ.get('EVIDENCE_FILE', '')

evidence = {
    "phase_id": phase_id,
    "attempt": attempt,
    "worker_name": "phase-executor",
    "goal_summary": "",
    "planned_output": "",
    "changed_files": [],
    "commands_run": [],
    "command_exit_codes": [],
    "tests_run": [],
    "test_results": {
        "total": 0,
        "passed": 0,
        "failed": 0,
        "skipped": 0
    },
    "lint_results": {
        "errors": 0,
        "warnings": 0
    },
    "build_results": {
        "success": True,
        "errors": []
    },
    "screenshots": [],
    "traces": [],
    "console_errors": [],
    "network_findings": [],
    "diff_summary": "",
    "artifact_paths": [],
    "unresolved_risks": [],
    "verification_gaps": [],
    "generated_at": timestamp
}

try:
    with open(evidence_file, 'w') as f:
        json.dump(evidence, f, indent=2)
    print(f"Evidence bundle template created: {evidence_file}")
    print("Worker should fill in the actual data.")
except Exception as e:
    print(f"Error creating evidence file: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
