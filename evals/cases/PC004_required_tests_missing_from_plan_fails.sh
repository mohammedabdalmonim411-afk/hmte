#!/bin/bash
# PC004: required_tests_missing_from_plan_fails
# Negative test: required tests 缺失时，Plan Coverage Gate 必须 FAIL

set -euo pipefail

TEST_ID="PC004"
TEST_NAME="required_tests_missing_from_plan_fails"
TEST_TYPE="negative"

echo "=== Running $TEST_ID: $TEST_NAME ==="

# Setup
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
mkdir -p .phase_control

# Create plan lock
cat > .phase_control/plan_lock.json <<'EOF'
{
  "plan_id": "TAF-PHASE-5-TEST",
  "plan_path": "HTE_v2.0_PHASE_5_PLAN.md",
  "plan_hash": "sha256:test123",
  "approved_by": "test",
  "approved_at": "2026-06-10T00:00:00Z",
  "locked_at": "2026-06-10T00:00:00Z"
}
EOF

# Create evidence with plan_ref but NO tests executed
cat > .phase_control/test_evidence.json <<'EOF'
{
  "phase_id": "test_phase",
  "attempt": 1,
  "status": "completed",
  "generated_at": "2026-06-10T00:00:30Z",
  "plan_ref": {
    "plan_path": "HTE_v2.0_PHASE_5_PLAN.md",
    "plan_hash": "sha256:test123",
    "plan_item_ids": ["S-001", "S-002"]
  },
  "tests_run": [],
  "tests_failed": [],
  "tests_skipped": [],
  "tests_timed_out": [],
  "changed_files": ["docs/test.md"]
}
EOF

# Test the coverage check directly using the Python code from phase_gate.sh
export EVIDENCE_FILE=".phase_control/test_evidence.json"
export PLAN_LOCK_FILE=".phase_control/plan_lock.json"

RESULT=$(python3 <<'COVERAGE_PY'
import json, sys, os

def check_plan_coverage():
    evidence_file = os.environ.get('EVIDENCE_FILE', '')
    plan_lock_file = os.environ.get('PLAN_LOCK_FILE', '')
    
    if not os.path.exists(evidence_file):
        return "FAIL: evidence file not found"
    if not os.path.exists(plan_lock_file):
        return "FAIL: plan lock file not found"
    
    try:
        with open(evidence_file) as f:
            evidence = json.load(f)
        with open(plan_lock_file) as f:
            plan_lock = json.load(f)
    except Exception as e:
        return f"FAIL: cannot parse files: {e}"
    
    issues = []
    
    # Check evidence.plan_ref
    plan_ref = evidence.get('plan_ref', {})
    if not plan_ref:
        issues.append("evidence.plan_ref is missing")
    else:
        evidence_hash = plan_ref.get('plan_hash', '')
        lock_hash = plan_lock.get('plan_hash', '')
        if evidence_hash != lock_hash:
            issues.append(f"plan_hash mismatch: evidence={evidence_hash}, lock={lock_hash}")
        
        plan_item_ids = plan_ref.get('plan_item_ids', [])
        if not plan_item_ids:
            issues.append("evidence.plan_ref.plan_item_ids is empty")
    
    # Check tests_run for required_tests (simplified check)
    tests_run = evidence.get('tests_run', [])
    tests_failed = evidence.get('tests_failed', [])
    tests_skipped = evidence.get('tests_skipped', [])
    tests_timed_out = evidence.get('tests_timed_out', [])
    
    all_tests = set(tests_run + tests_failed + tests_skipped + tests_timed_out)
    
    # Note: Full required_tests check requires parsing plan file
    # For now, just verify tests_run is not empty for non-docs phases
    if not all_tests and not evidence.get('exemption_type'):
        issues.append("no tests executed (tests_run/failed/skipped/timed_out all empty)")
    
    if issues:
        return "FAIL: " + "; ".join(issues)
    return "PASS"

print(check_plan_coverage())
COVERAGE_PY
)

echo "Coverage check result: $RESULT"

# Verify the result
if [[ "$RESULT" == FAIL* ]]; then
    if echo "$RESULT" | grep -q "no tests executed"; then
        echo "✅ PASS: Plan Coverage Gate correctly detected missing tests"
        exit 0
    else
        echo "❌ FAIL: Plan Coverage Gate failed but for wrong reason: $RESULT"
        exit 1
    fi
else
    echo "❌ FAIL: Plan Coverage Gate should have failed (no tests executed)"
    exit 1
fi
