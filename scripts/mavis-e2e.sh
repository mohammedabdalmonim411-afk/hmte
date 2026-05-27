#!/bin/bash
# End-to-End test for HMTE

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== HMTE E2E Test ==="
echo ""

# Cleanup previous test
echo "Cleaning up previous test..."
./scripts/mavis-stop.sh 2>/dev/null || true
rm -rf .phase_control/evidence/* .phase_control/verdicts/* .phase_control/logs/*
rm -f .phase_control/phases.yaml .phase_control/state.json .phase_control/current_phase

# Start fresh session
echo "Starting new session..."
./scripts/mavis-start.sh

# Check state file created
if [ ! -f ".phase_control/state.json" ]; then
    echo "FAIL: state.json not created"
    exit 1
fi
echo "✓ State file created"

# Create test phases.yaml
echo "Creating test phases..."
cat > .phase_control/phases.yaml << 'PHASES_EOF'
phases:
  - id: phase_test
    name: "Test Phase"
    objective: "Verify HMTE works"
    inputs:
      - "Test input"
    outputs:
      - "Test output"
    acceptance_criteria:
      - "Evidence bundle created"
      - "All required fields present"
    required_evidence:
      - "changed_files"
      - "commands_run"
    timeout_soft: 60
    timeout_hard: 120
    max_retries: 2
    escalation_rule: "Test escalation"
PHASES_EOF
echo "✓ Test phases created"

# Create test evidence bundle
echo "Creating test evidence..."
mkdir -p .phase_control/evidence
cat > .phase_control/evidence/phase_test_attempt_1.json << 'EVIDENCE_EOF'
{
  "phase_id": "phase_test",
  "attempt": 1,
  "worker_name": "test-worker",
  "goal_summary": "Test evidence generation",
  "planned_output": "Test output",
  "changed_files": ["test.txt"],
  "commands_run": ["echo test"],
  "command_exit_codes": [0],
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
    "success": true,
    "errors": []
  },
  "screenshots": [],
  "traces": [],
  "console_errors": [],
  "network_findings": [],
  "diff_summary": "Test changes",
  "artifact_paths": ["test.txt"],
  "unresolved_risks": [],
  "verification_gaps": [],
  "generated_at": "2026-05-26T12:00:00Z"
}
EVIDENCE_EOF
echo "✓ Test evidence created"

# Verify evidence schema
echo "Validating evidence schema..."
if command -v jq &> /dev/null; then
    jq empty .phase_control/evidence/phase_test_attempt_1.json
    echo "✓ Evidence JSON valid"
else
    echo "⚠ jq not found, skipping JSON validation"
fi

# Create test verdict (PASS)
echo "Creating test verdict..."
mkdir -p .phase_control/verdicts
cat > .phase_control/verdicts/phase_test_attempt_1.txt << 'VERDICT_EOF'
VERDICT: PASS
PHASE_ID: phase_test
CONFIDENCE: high
ACCEPTANCE_CHECKS:
- [x] Evidence bundle created
- [x] All required fields present
RESIDUAL_RISKS:
- None (test only)
EVIDENCE_USED:
- .phase_control/evidence/phase_test_attempt_1.json
NEXT_ACTION: RELEASE_TO_NEXT_PHASE
VERDICT_EOF
echo "✓ Test verdict created"

# Update state to passed
echo "Updating state..."
if command -v jq &> /dev/null; then
    jq '.current_phase = "phase_test" | .phase_status = "passed"' .phase_control/state.json > .phase_control/state.json.tmp
    mv .phase_control/state.json.tmp .phase_control/state.json
    echo "✓ State updated"
else
    echo "⚠ jq not found, skipping state update"
fi

# Check status
echo ""
echo "Checking status..."
./scripts/mavis-status.sh

# Verify stop gate allows stopping
echo ""
echo "Testing stop gate..."
if .claude/hooks/stop_gate.sh; then
    echo "✓ Stop gate allows stopping (phase passed)"
else
    echo "FAIL: Stop gate blocked stopping"
    exit 1
fi

# Test FAIL scenario
echo ""
echo "Testing FAIL scenario..."
cat > .phase_control/verdicts/phase_test_attempt_2.txt << 'VERDICT_EOF'
VERDICT: FAIL
PHASE_ID: phase_test
CONFIDENCE: high
FAILED_CHECKS:
- [ ] Test intentionally failed
ROOT_CAUSES:
- Testing FAIL path
REQUIRED_REWORK:
- Fix the issue
EVIDENCE_USED:
- .phase_control/evidence/phase_test_attempt_1.json
NEXT_ACTION: RETURN_TO_EXECUTOR
VERDICT_EOF

# Update state to failed
if command -v jq &> /dev/null; then
    jq '.phase_status = "failed"' .phase_control/state.json > .phase_control/state.json.tmp
    mv .phase_control/state.json.tmp .phase_control/state.json
fi

# Verify stop gate blocks stopping
if .claude/hooks/stop_gate.sh 2>/dev/null; then
    echo "FAIL: Stop gate should block when phase failed"
    exit 1
else
    echo "✓ Stop gate correctly blocks incomplete work"
fi

# Cleanup
echo ""
echo "Cleaning up..."
./scripts/mavis-stop.sh

echo ""
echo "=== E2E Test PASSED ==="
echo ""
echo "Verified:"
echo "  ✓ Session initialization"
echo "  ✓ Phase definition"
echo "  ✓ Evidence bundle creation"
echo "  ✓ Verdict format"
echo "  ✓ State management"
echo "  ✓ Stop gate enforcement"
echo ""
echo "HMTE is ready to use!"
echo "Invoke the 'mavis-team-engine' skill in Hermes to get started."
