#!/usr/bin/env bash
#
# PC001: missing_plan_lock_blocks_start
#
# Test that execution is blocked when plan_lock.json is missing
#

set -euo pipefail

TEST_NAME="PC001_missing_plan_lock_blocks_start"
TEST_DIR=".phase_control/test_${TEST_NAME}"

echo "Running test: $TEST_NAME"
echo "════════════════════════════════════════════════════════════════"

# Setup
mkdir -p "$TEST_DIR"

# Create a test plan
cat > "$TEST_DIR/test_plan.md" <<'EOF'
# Plan Contract

**Plan ID**: TEST-001  
**Version**: 1.0  
**Project**: Test Plan  
**Status**: draft  

## Scope

| ID | Item | Priority | Description |
|----|------|----------|-------------|
| S-001 | Test Item | P0 | Test |

## Non-Scope

| ID | Item | Reason |
|----|------|--------|
| NS-001 | Test Non-Scope | Test |

## Phases

| ID | Phase | Goal | Plan Items |
|----|-------|------|------------|
| P-001 | Test Phase | Test | S-001 |

## Acceptance Criteria

| ID | Criterion | Related Plan Item | Verification Method |
|----|-----------|-------------------|---------------------|
| AC-001 | Test | S-001 | manual |

## Required Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| T-001 | Test | P-001 | positive |

## Required Negative Tests

| ID | Test | Phase | Type |
|----|------|-------|------|
| NT-001 | Test | P-001 | negative |

## Allowed Files

| ID | Path | Reason |
|----|------|--------|
| A-001 | test/ | Test |

## Forbidden Files

| ID | Path | Reason |
|----|------|--------|
| F-001 | prod/ | Test |

## Risk Register

| ID | Risk | Level | Mitigation |
|----|------|-------|------------|
| R-001 | Test | P1 | Test |

## Dogfood Requirements

| ID | Requirement | Verification |
|----|-------------|--------------|
| D-001 | Test | Test |

## Release Conditions

| ID | Condition | Verification |
|----|-----------|--------------|
| RC-001 | Test | Test |

## Stop Conditions

| ID | Condition | Action |
|----|-----------|--------|
| SC-001 | Test | BLOCK |
EOF

# Test: Try to verify without lock file (should fail)
echo ""
echo "Test: Verify plan without lock file"

# Run and capture both stdout and exit code
set +e
OUTPUT=$(bash scripts/hmte-plan-lock.sh --plan "$TEST_DIR/test_plan.md" --verify --lock "$TEST_DIR/plan_lock.json" 2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ] && echo "$OUTPUT" | grep -q "Lock file not found"; then
  echo "✅ PASS: Correctly blocked execution when plan_lock.json is missing"
  RESULT=0
else
  echo "❌ FAIL: Did not block execution when plan_lock.json is missing"
  echo "   Exit code: $EXIT_CODE"
  echo "   Output: $OUTPUT"
  RESULT=1
fi

# Cleanup
rm -rf "$TEST_DIR"

echo "════════════════════════════════════════════════════════════════"
if [ $RESULT -eq 0 ]; then
  echo "✅ Test $TEST_NAME: PASS"
else
  echo "❌ Test $TEST_NAME: FAIL"
fi

exit $RESULT
