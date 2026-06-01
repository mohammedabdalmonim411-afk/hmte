#!/bin/bash
# Test Phase 2: Amendment Validation (reason length, hash binding, release mode)
set -euo pipefail

echo "=========================================="
echo "Phase 2 Test: Amendment Validation"
echo "=========================================="
echo ""

# Get the original working directory
ORIGINAL_DIR="$(pwd)"
SCRIPT_DIR="$ORIGINAL_DIR/scripts"

# Test 1: Reason length validation for add_phase
echo "Test 1: add_phase reason length validation"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
mkdir -p .phase_control/{amendments,instructions,delegations,logs,evidence,verdicts}
mkdir -p src/skills/hmte/scripts

# Copy phase_gate and audit-flow
cp "$ORIGINAL_DIR/src/skills/hmte/scripts/phase_gate.sh" src/skills/hmte/scripts/
cp "$ORIGINAL_DIR/src/skills/hmte/scripts/hmte-audit-flow.py" src/skills/hmte/scripts/

cat > .phase_control/session.json <<'EOF'
{"task": "test", "session_id": "test-001"}
EOF

cat > .phase_control/phases.json <<'EOF'
{
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A"]},
    {"phase_id": "phase_2", "name": "Phase 2", "acceptance_criteria": ["Criteria B"]}
  ]
}
EOF

cat > .phase_control/goal_lock.json <<'EOF'
{
  "task": "test",
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A"], "criteria_hash": "abc123"}
  ],
  "created_at": "2026-06-01T00:00:00Z"
}
EOF

# Amendment with reason too short (< 20 chars)
cat > .phase_control/amendments/add_phase_2.json <<'EOF'
{
  "action": "add_phase",
  "phase_id": "phase_2",
  "reason": "Too short",
  "new_hash": "def456",
  "timestamp": "2026-06-01T01:00:00Z"
}
EOF

# Run final-check in release mode - should FAIL due to short reason
if bash "$SCRIPT_DIR/hmte-final-check.sh" --mode release >/dev/null 2>&1; then
    echo "❌ FAIL: Should reject add_phase with short reason"
    cd /
    rm -rf "$TEST_DIR"
    exit 1
else
    echo "✅ PASS: Correctly rejected add_phase with short reason (< 20 chars)"
fi

cd /
rm -rf "$TEST_DIR"

# Test 2: Reason length validation for modify_criteria
echo ""
echo "Test 2: modify_criteria reason length validation"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
mkdir -p .phase_control/{amendments,instructions,delegations,logs,evidence,verdicts}
mkdir -p src/skills/hmte/scripts

cp "$ORIGINAL_DIR/src/skills/hmte/scripts/phase_gate.sh" src/skills/hmte/scripts/
cp "$ORIGINAL_DIR/src/skills/hmte/scripts/hmte-audit-flow.py" src/skills/hmte/scripts/

cat > .phase_control/session.json <<'EOF'
{"task": "test", "session_id": "test-001"}
EOF

cat > .phase_control/phases.json <<'EOF'
{
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A modified"]}
  ]
}
EOF

cat > .phase_control/goal_lock.json <<'EOF'
{
  "task": "test",
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A", "Criteria B"], "criteria_hash": "abc123"}
  ],
  "created_at": "2026-06-01T00:00:00Z"
}
EOF

# Amendment with reason too short (< 30 chars)
cat > .phase_control/amendments/modify_phase_1.json <<'EOF'
{
  "action": "modify_criteria",
  "phase_id": "phase_1",
  "old": "Criteria A",
  "new": "Criteria A modified",
  "reason": "Short reason here",
  "new_hash": "def456",
  "timestamp": "2026-06-01T01:00:00Z"
}
EOF

# Run final-check in release mode - should FAIL due to short reason
if bash "$SCRIPT_DIR/hmte-final-check.sh" --mode release >/dev/null 2>&1; then
    echo "❌ FAIL: Should reject modify_criteria with short reason"
    cd /
    rm -rf "$TEST_DIR"
    exit 1
else
    echo "✅ PASS: Correctly rejected modify_criteria with short reason (< 30 chars)"
fi

cd /
rm -rf "$TEST_DIR"

# Test 3: Hash binding check for add_phase
echo ""
echo "Test 3: Hash binding check for add_phase"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
mkdir -p .phase_control/{amendments,instructions,delegations,logs,evidence,verdicts}
mkdir -p src/skills/hmte/scripts

cp "$ORIGINAL_DIR/src/skills/hmte/scripts/phase_gate.sh" src/skills/hmte/scripts/
cp "$ORIGINAL_DIR/src/skills/hmte/scripts/hmte-audit-flow.py" src/skills/hmte/scripts/

cat > .phase_control/session.json <<'EOF'
{"task": "test", "session_id": "test-001"}
EOF

cat > .phase_control/phases.json <<'EOF'
{
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A"]},
    {"phase_id": "phase_2", "name": "Phase 2", "acceptance_criteria": ["Criteria B"]}
  ]
}
EOF

cat > .phase_control/goal_lock.json <<'EOF'
{
  "task": "test",
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A"], "criteria_hash": "abc123"}
  ],
  "created_at": "2026-06-01T00:00:00Z"
}
EOF

# Compute correct hash for phase_2
CORRECT_HASH=$(python3 -c "import hashlib; print(hashlib.sha256('Criteria B'.encode()).hexdigest())")

# Amendment with WRONG hash
cat > .phase_control/amendments/add_phase_2.json <<EOF
{
  "action": "add_phase",
  "phase_id": "phase_2",
  "reason": "This is a valid reason with sufficient length for add_phase",
  "new_hash": "wrong_hash_value_here",
  "timestamp": "2026-06-01T01:00:00Z"
}
EOF

# Run final-check in release mode - should FAIL due to hash mismatch
if bash "$SCRIPT_DIR/hmte-final-check.sh" --mode release >/dev/null 2>&1; then
    echo "❌ FAIL: Should reject add_phase with wrong hash"
    cd /
    rm -rf "$TEST_DIR"
    exit 1
else
    echo "✅ PASS: Correctly rejected add_phase with hash mismatch"
fi

cd /
rm -rf "$TEST_DIR"

# Test 4: Release mode blocks scope_impact=reduce
echo ""
echo "Test 4: Release mode blocks scope_impact=reduce"
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
mkdir -p .phase_control/{amendments,instructions,delegations,logs,evidence,verdicts}
mkdir -p src/skills/hmte/scripts

cp "$ORIGINAL_DIR/src/skills/hmte/scripts/phase_gate.sh" src/skills/hmte/scripts/
cp "$ORIGINAL_DIR/src/skills/hmte/scripts/hmte-audit-flow.py" src/skills/hmte/scripts/

cat > .phase_control/session.json <<'EOF'
{"task": "test", "session_id": "test-001"}
EOF

cat > .phase_control/phases.json <<'EOF'
{
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A"]},
    {"phase_id": "phase_2", "name": "Phase 2", "acceptance_criteria": ["Criteria B"]}
  ]
}
EOF

cat > .phase_control/goal_lock.json <<'EOF'
{
  "task": "test",
  "phases": [
    {"phase_id": "phase_1", "name": "Phase 1", "acceptance_criteria": ["Criteria A"], "criteria_hash": "abc123"}
  ],
  "created_at": "2026-06-01T00:00:00Z"
}
EOF

# Compute correct hash for phase_2
CORRECT_HASH=$(python3 -c "import hashlib; print(hashlib.sha256('Criteria B'.encode()).hexdigest())")

# Amendment with scope_impact=reduce
cat > .phase_control/amendments/add_phase_2.json <<EOF
{
  "action": "add_phase",
  "phase_id": "phase_2",
  "reason": "This is a valid reason with sufficient length for add_phase",
  "new_hash": "$CORRECT_HASH",
  "scope_impact": "reduce",
  "timestamp": "2026-06-01T01:00:00Z"
}
EOF

# Run final-check in release mode - should FAIL due to scope_impact=reduce
if bash "$SCRIPT_DIR/hmte-final-check.sh" --mode release >/dev/null 2>&1; then
    echo "❌ FAIL: Should block scope_impact=reduce in release mode"
    cd /
    rm -rf "$TEST_DIR"
    exit 1
else
    echo "✅ PASS: Correctly blocked scope_impact=reduce in release mode"
fi

cd /
rm -rf "$TEST_DIR"

echo ""
echo "=========================================="
echo "All Phase 2 amendment validation tests passed!"
echo "=========================================="
