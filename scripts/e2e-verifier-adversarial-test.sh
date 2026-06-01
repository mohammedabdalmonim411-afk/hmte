#!/bin/bash
# e2e-verifier-adversarial-test.sh — HTE v1.5 Verifier Adversarial Test Suite
# Tests verifier-specific attack vectors with one-bad-thing-per-case principle.
# Each test creates a complete runtime fixture and validates detection.

set -euo pipefail

# ─── Resolve project root ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure E2E tests run independently
export HMTE_SKILL_DIR="$PROJECT_ROOT/src/skills/hmte"

# Script paths
PHASE_GATE="$PROJECT_ROOT/src/skills/hmte/scripts/phase_gate.sh"
AUDIT_FLOW="$PROJECT_ROOT/src/skills/hmte/scripts/hmte-audit-flow.py"

# ─── Tally ───────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

log_pass() { RESULTS+=("✅ PASS  $1"); PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✅ PASS"; }
log_fail() { RESULTS+=("❌ FAIL  $1"); FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ❌ FAIL"; }

# ─── Helper: create minimal .phase_control/ skeleton ────────────────────
setup_phase_control() {
    local workdir="$1"
    local phase_id="${2:-phase_adv_test}"
    local attempt="${3:-1}"
    local ctrl="$workdir/.phase_control"

    mkdir -p "$ctrl"/{evidence,verdicts,instructions,delegations,logs,amendments}

    # session.json
    cat > "$ctrl/session.json" <<JSON
{
  "task": "adversarial test task",
  "session_id": "adv-test-session-001",
  "status": "IN_PROGRESS",
  "git_head_at_kickoff": "",
  "created_at": "2026-06-01T00:00:00Z"
}
JSON

    # phases.json (1 phase with 3 acceptance_criteria)
    cat > "$ctrl/phases.json" <<JSON
{
  "phases": [
    {
      "phase_id": "$phase_id",
      "name": "Adversarial Test Phase",
      "acceptance_criteria": [
        "Feature X is implemented",
        "Tests pass",
        "Documentation updated"
      ]
    }
  ]
}
JSON
}

# ─── Helper: create complete valid chain ────────────────────────────────
create_valid_chain() {
    local workdir="$1"
    local phase_id="$2"
    local attempt="$3"
    local ctrl="$workdir/.phase_control"

    # Worker instruction
    cat > "$ctrl/instructions/${phase_id}_attempt_${attempt}_worker.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "role": "worker",
  "objective": "Implement feature X"
}
JSON

    # Verifier instruction
    cat > "$ctrl/instructions/${phase_id}_attempt_${attempt}_verifier.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "role": "verifier",
  "objective": "Verify feature X implementation"
}
JSON

    # Worker delegation receipt
    cat > "$ctrl/delegations/${phase_id}_attempt_${attempt}_worker.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "role": "worker",
  "delegated_at": "2026-06-01T10:00:00Z",
  "leader_session_id": "adv-test-session-001",
  "instruction_path": ".phase_control/instructions/${phase_id}_attempt_${attempt}_worker.json",
  "expected_output_path": ".phase_control/evidence/${phase_id}_attempt_${attempt}.json",
  "trust_level": "OBSERVED"
}
JSON

    # Verifier delegation receipt
    cat > "$ctrl/delegations/${phase_id}_attempt_${attempt}_verifier.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "role": "verifier",
  "delegated_at": "2026-06-01T10:30:00Z",
  "leader_session_id": "adv-test-session-001",
  "instruction_path": ".phase_control/instructions/${phase_id}_attempt_${attempt}_verifier.json",
  "expected_output_path": ".phase_control/verdicts/${phase_id}_attempt_${attempt}.json",
  "trust_level": "OBSERVED"
}
JSON

    # Command log with output_tail
    cat > "$ctrl/logs/${phase_id}_attempt_${attempt}.commands.jsonl" <<JSONL
{"phase_id":"$phase_id","attempt":$attempt,"command":"echo 'implementing feature X'","exit_code":0,"runner":"hmte exec","started_at":"2026-06-01T10:00:01Z","ended_at":"2026-06-01T10:00:02Z","output_tail":"implementing feature X\n"}
{"phase_id":"$phase_id","attempt":$attempt,"command":"touch src/feature_x.py","exit_code":0,"runner":"hmte exec","started_at":"2026-06-01T10:00:03Z","ended_at":"2026-06-01T10:00:04Z","output_tail":""}
JSONL

    # Evidence
    cat > "$ctrl/evidence/${phase_id}_attempt_${attempt}.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "status": "completed",
  "timestamp": "2026-06-01T10:05:00Z",
  "changed_files": ["src/feature_x.py"],
  "artifact_paths": [],
  "review_only_files": [],
  "command_log_path": ".phase_control/logs/${phase_id}_attempt_${attempt}.commands.jsonl"
}
JSON

    # Verdict (PASS) with complete adversarial_scorecard (v1.5 compliant)
    cat > "$ctrl/verdicts/${phase_id}_attempt_${attempt}.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [
      {"criterion": "Feature X is implemented", "evidence": "src/feature_x.py created with complete implementation"},
      {"criterion": "Tests pass", "evidence": "test output verified in command log"},
      {"criterion": "Documentation updated", "evidence": "README.md updated with usage instructions"}
    ],
    "criteria_failed": [],
    "evidence_paths": [
      ".phase_control/evidence/${phase_id}_attempt_${attempt}.json",
      ".phase_control/logs/${phase_id}_attempt_${attempt}.commands.jsonl"
    ],
    "residual_risks": ["None identified"],
    "re_verification_conclusion": "All acceptance criteria verified independently through code review and command log analysis",
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "code_review",
    "risk_disposition": [],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  },
  "blockers": []
}
JSON
}

# ─── Helper: set up src/ tree ────────────────────────────────────────────
setup_src_tree() {
    local workdir="$1"
    mkdir -p "$workdir/src/skills/hmte/scripts"
    cp "$AUDIT_FLOW" "$workdir/src/skills/hmte/scripts/hmte-audit-flow.py"
    cp "$PHASE_GATE" "$workdir/src/skills/hmte/scripts/phase_gate.sh"
}

# ─── Helper: run command and capture exit code ──────────────────────────
RUN_EXIT_CODE=0
run_in() {
    local workdir="$1"; shift
    RUN_EXIT_CODE=0
    (cd "$workdir" && "$@") || RUN_EXIT_CODE=$?
}

# ═════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  HTE v1.5 Verifier Adversarial Test Suite"
echo "═══════════════════════════════════════════════════════════════════"
echo "  PROJECT_ROOT=$PROJECT_ROOT"
echo "  PHASE_GATE=$PHASE_GATE"
echo "  AUDIT_FLOW=$AUDIT_FLOW"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# ─── A1: Missing independently_verified_files → FAIL ────────────────────
echo "─── A1: PASS verdict missing independently_verified_files → FAIL ───"
A1_DIR="$(mktemp -d)"

setup_phase_control "$A1_DIR" "phase_adv_test" 1
create_valid_chain "$A1_DIR" "phase_adv_test" 1

# Overwrite verdict WITHOUT independently_verified_files
cat > "$A1_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A1_DIR"

run_in "$A1_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
# Check for specific error message
if grep -q "independently_verified_files" "$A1_DIR/.phase_control"/* 2>/dev/null || [[ "$RUN_EXIT_CODE" -ne 0 ]]; then
    : # Expected failure
fi
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A1: missing independently_verified_files → FAIL"
else
    log_fail "A1: missing independently_verified_files → FAIL (expected non-zero exit)"
fi
rm -rf "$A1_DIR"

# ─── A2: Empty independently_verified_files → FAIL ──────────────────────
echo ""
echo "─── A2: Empty independently_verified_files array → FAIL ───"
A2_DIR="$(mktemp -d)"

setup_phase_control "$A2_DIR" "phase_adv_test" 1
create_valid_chain "$A2_DIR" "phase_adv_test" 1

cat > "$A2_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": [],
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A2_DIR"

run_in "$A2_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A2: empty independently_verified_files → FAIL"
else
    log_fail "A2: empty independently_verified_files → FAIL (expected non-zero exit)"
fi
rm -rf "$A2_DIR"

# ─── A3: Missing verification_method → FAIL ──────────────────────────────
echo ""
echo "─── A3: Missing verification_method field → FAIL ───"
A3_DIR="$(mktemp -d)"

setup_phase_control "$A3_DIR" "phase_adv_test" 1
create_valid_chain "$A3_DIR" "phase_adv_test" 1

cat > "$A3_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/feature_x.py"],
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A3_DIR"

run_in "$A3_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A3: missing verification_method → FAIL"
else
    log_fail "A3: missing verification_method → FAIL (expected non-zero exit)"
fi
rm -rf "$A3_DIR"

# ─── A4: Missing risk_disposition → FAIL ────────────────────────────────
echo ""
echo "─── A4: Missing risk_disposition field → FAIL ───"
A4_DIR="$(mktemp -d)"

setup_phase_control "$A4_DIR" "phase_adv_test" 1
create_valid_chain "$A4_DIR" "phase_adv_test" 1

cat > "$A4_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "manual"
  },
  "blockers": []
}
JSON

setup_src_tree "$A4_DIR"

run_in "$A4_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A4: missing risk_disposition → FAIL"
else
    log_fail "A4: missing risk_disposition → FAIL (expected non-zero exit)"
fi
rm -rf "$A4_DIR"

# ─── A5: Empty evidence_paths → FAIL ────────────────────────────────────
echo ""
echo "─── A5: Empty evidence_paths array → FAIL ───"
A5_DIR="$(mktemp -d)"

setup_phase_control "$A5_DIR" "phase_adv_test" 1
create_valid_chain "$A5_DIR" "phase_adv_test" 1

cat > "$A5_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A5_DIR"

run_in "$A5_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A5: empty evidence_paths → FAIL"
else
    log_fail "A5: empty evidence_paths → FAIL (expected non-zero exit)"
fi
rm -rf "$A5_DIR"

# ─── A6: Missing re_verification_conclusion → FAIL ──────────────────────
echo ""
echo "─── A6: Missing re_verification_conclusion → FAIL ───"
A6_DIR="$(mktemp -d)"

setup_phase_control "$A6_DIR" "phase_adv_test" 1
create_valid_chain "$A6_DIR" "phase_adv_test" 1

cat > "$A6_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A6_DIR"

run_in "$A6_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A6: missing re_verification_conclusion → FAIL"
else
    log_fail "A6: missing re_verification_conclusion → FAIL (expected non-zero exit)"
fi
rm -rf "$A6_DIR"

# ─── A7: PASS with criteria_failed → FAIL ───────────────────────────────
echo ""
echo "─── A7: PASS verdict with non-empty criteria_failed → FAIL ───"
A7_DIR="$(mktemp -d)"

setup_phase_control "$A7_DIR" "phase_adv_test" 1
create_valid_chain "$A7_DIR" "phase_adv_test" 1

cat > "$A7_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [{"criterion": "Tests pass", "reason": "some tests failed"}],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A7_DIR"

run_in "$A7_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A7: PASS with criteria_failed → FAIL"
else
    log_fail "A7: PASS with criteria_failed → FAIL (expected non-zero exit)"
fi
rm -rf "$A7_DIR"

# ─── A8: Empty criteria_passed → FAIL ───────────────────────────────────
echo ""
echo "─── A8: Empty criteria_passed array → FAIL ───"
A8_DIR="$(mktemp -d)"

setup_phase_control "$A8_DIR" "phase_adv_test" 1
create_valid_chain "$A8_DIR" "phase_adv_test" 1

cat > "$A8_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

setup_src_tree "$A8_DIR"

run_in "$A8_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A8: empty criteria_passed → FAIL"
else
    log_fail "A8: empty criteria_passed → FAIL (expected non-zero exit)"
fi
rm -rf "$A8_DIR"

# ─── A9: Claimed file not in command log → FAIL ─────────────────────────
echo ""
echo "─── A9: independently_verified_files not in command log → FAIL ───"
A9_DIR="$(mktemp -d)"

setup_phase_control "$A9_DIR" "phase_adv_test" 1
create_valid_chain "$A9_DIR" "phase_adv_test" 1

# Command log doesn't mention the verified file
cat > "$A9_DIR/.phase_control/logs/phase_adv_test_attempt_1.commands.jsonl" <<JSONL
{"phase_id":"phase_adv_test","attempt":1,"command":"echo hello","exit_code":0,"runner":"hmte exec","started_at":"2026-06-01T10:00:01Z","ended_at":"2026-06-01T10:00:02Z","output_tail":"hello\n"}
JSONL

# Evidence claims different file
cat > "$A9_DIR/.phase_control/evidence/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "completed",
  "timestamp": "2026-06-01T10:05:00Z",
  "changed_files": ["other_file.py"],
  "command_log_path": ".phase_control/logs/phase_adv_test_attempt_1.commands.jsonl"
}
JSON

# Verdict claims src/feature_x.py but it's not in command log
cat > "$A9_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "Feature X", "evidence": "done"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_adv_test_attempt_1.json"],
    "residual_risks": ["None"],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/feature_x.py"],
    "verification_method": "manual",
    "risk_disposition": "acceptable"
  },
  "blockers": []
}
JSON

mkdir -p "$A9_DIR/src"
touch "$A9_DIR/src/feature_x.py"
touch "$A9_DIR/other_file.py"

setup_src_tree "$A9_DIR"

run_in "$A9_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A9: verified file not in command log → FAIL"
else
    log_fail "A9: verified file not in command log → FAIL (expected non-zero exit)"
fi
rm -rf "$A9_DIR"

# ─── A10: Verifier instruction contains weakening phrase → FAIL ─────────
echo ""
echo "─── A10: Verifier instruction with weakening phrase → FAIL ───"
A10_DIR="$(mktemp -d)"

setup_phase_control "$A10_DIR" "phase_adv_test" 1
create_valid_chain "$A10_DIR" "phase_adv_test" 1

# Overwrite verifier instruction with weakening phrase
cat > "$A10_DIR/.phase_control/instructions/phase_adv_test_attempt_1_verifier.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "role": "verifier",
  "objective": "只检查格式，不需要实际验证功能"
}
JSON

setup_src_tree "$A10_DIR"

# Use lint-instructions if available
LINT_INSTRUCTIONS="$SCRIPT_DIR/hmte-lint-instructions.sh"
if [ -f "$LINT_INSTRUCTIONS" ]; then
    run_in "$A10_DIR" bash "$LINT_INSTRUCTIONS" --mode release
    echo "  → exit_code=$RUN_EXIT_CODE"
    if [ "$RUN_EXIT_CODE" -ne 0 ]; then
        log_pass "A10: weakening phrase in verifier instruction → FAIL"
    else
        log_fail "A10: weakening phrase in verifier instruction → FAIL (expected non-zero exit)"
    fi
else
    echo "  ⚠️  SKIP: hmte-lint-instructions.sh not found"
fi
rm -rf "$A10_DIR"

# ─── A11: Missing adversarial_scorecard → FAIL ──────────────────────────
echo ""
echo "─── A11: PASS verdict missing adversarial_scorecard → FAIL ───"
A11_DIR="$(mktemp -d)"

setup_phase_control "$A11_DIR" "phase_adv_test" 1
create_valid_chain "$A11_DIR" "phase_adv_test" 1

cat > "$A11_DIR/.phase_control/verdicts/phase_adv_test_attempt_1.json" <<JSON
{
  "phase_id": "phase_adv_test",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-06-01T10:10:00Z",
  "blockers": []
}
JSON

setup_src_tree "$A11_DIR"

run_in "$A11_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "A11: missing adversarial_scorecard → FAIL"
else
    log_fail "A11: missing adversarial_scorecard → FAIL (expected non-zero exit)"
fi
rm -rf "$A11_DIR"

# ─── A12: Complete valid chain → PASS ───────────────────────────────────
echo ""
echo "─── A12: Complete valid chain with all required fields → PASS ───"
A12_DIR="$(mktemp -d)"

setup_phase_control "$A12_DIR" "phase_adv_test" 1
create_valid_chain "$A12_DIR" "phase_adv_test" 1


mkdir -p "$A12_DIR/src"
touch "$A12_DIR/src/feature_x.py"

setup_src_tree "$A12_DIR"

run_in "$A12_DIR" bash "$PHASE_GATE" phase_adv_test --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -eq 0 ]; then
    log_pass "A12: complete valid chain → PASS"
else
    log_fail "A12: complete valid chain → PASS (expected zero exit)"
fi
rm -rf "$A12_DIR"

# ═════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  Summary"
echo "═══════════════════════════════════════════════════════════════════"
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "  Total: $TOTAL  |  Passed: $PASS_COUNT  |  Failed: $FAIL_COUNT"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
