#!/bin/bash
# Test Phase 2: Hash Normalization and Amendment Validation
set -euo pipefail

echo "=========================================="
echo "Phase 2 Test: Hash Normalization"
echo "=========================================="
echo ""

# Get the original working directory before cd to TEST_DIR
ORIGINAL_DIR="$(pwd)"
SCRIPT_DIR="$ORIGINAL_DIR/scripts"

# Create a test directory
TEST_DIR=$(mktemp -d)
echo "Test directory: $TEST_DIR"

cd "$TEST_DIR"

# Setup minimal .phase_control
mkdir -p .phase_control

# Create session.json
cat > .phase_control/session.json <<'EOF'
{
  "task": "test task",
  "session_id": "test-001",
  "git_head_at_kickoff": "abc123"
}
EOF

# Create phases.json with criteria that have extra spaces
cat > .phase_control/phases.json <<'EOF'
{
  "phases": [
    {
      "phase_id": "test_phase",
      "name": "Test Phase",
      "acceptance_criteria": [
        "  Criteria A  ",
        "Criteria B",
        "",
        "  ",
        "Criteria C  "
      ]
    }
  ]
}
EOF

# Run goal-lock
echo "Running hmte-goal-lock.sh..."
bash "$SCRIPT_DIR/hmte-goal-lock.sh"

# Check if goal_lock.json was created
if [ -f .phase_control/goal_lock.json ]; then
    echo "✅ goal_lock.json created"

    # Extract the hash
    HASH=$(python3 -c "import json; print(json.load(open('.phase_control/goal_lock.json'))['phases'][0]['criteria_hash'])")
    echo "  Generated hash: ${HASH:0:16}..."

    # Compute expected hash with normalization
    EXPECTED=$(python3 -c "import hashlib; normalized=['Criteria A', 'Criteria B', 'Criteria C']; print(hashlib.sha256(''.join(normalized).encode()).hexdigest())")
    echo "  Expected hash:  ${EXPECTED:0:16}..."

    if [ "$HASH" = "$EXPECTED" ]; then
        echo "✅ Hash normalization works correctly"
    else
        echo "❌ Hash mismatch"
        cd /
        rm -rf "$TEST_DIR"
        exit 1
    fi
else
    echo "❌ goal_lock.json not created"
    cd /
    rm -rf "$TEST_DIR"
    exit 1
fi

# Cleanup
cd /
rm -rf "$TEST_DIR"

echo ""
echo "=========================================="
echo "All Phase 2 tests passed!"
echo "=========================================="
