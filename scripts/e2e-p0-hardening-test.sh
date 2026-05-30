#!/bin/bash
# e2e-p0-hardening-test.sh — HTE v1.4 P0 Hardening E2E Tests
# Tests 5 specific failure scenarios (T1–T5) that MUST exit non-zero.
# Each test runs in a mktemp -d isolation directory.
#
# IMPORTANT: These tests are written to the P0 SPECIFICATIONS.
# The scripts under test (final-check, lint-instructions, verify-claims,
# phase_gate) are being updated in parallel with P0 hardening features.
# All tests should pass once the P0 upgrades are complete.
set -euo pipefail

# ─── Resolve project root (where this script lives = scripts/) ────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure E2E tests run independently of local Hermes installation
export HMTE_SKILL_DIR="$PROJECT_ROOT/src/skills/hmte"

# Script paths (real scripts under test)
FINAL_CHECK="$SCRIPT_DIR/hmte-final-check.sh"
LINT_INSTRUCTIONS="$SCRIPT_DIR/hmte-lint-instructions.sh"
VERIFY_CLAIMS="$SCRIPT_DIR/hmte-verify-claims.sh"
LEADER_JAIL="$SCRIPT_DIR/hmte-leader-jail.sh"
PHASE_GATE="$PROJECT_ROOT/src/skills/hmte/scripts/phase_gate.sh"
AUDIT_FLOW="$PROJECT_ROOT/src/skills/hmte/scripts/hmte-audit-flow.py"

# ─── Tally ────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

log_pass() { RESULTS+=("✅ PASS  $1"); PASS_COUNT=$((PASS_COUNT + 1)); echo "  ✅ PASS"; }
log_fail() { RESULTS+=("❌ FAIL  $1"); FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  ❌ FAIL"; }

# ─── Helper: create minimal .phase_control/ skeleton ─────────────────────
# Usage: setup_phase_control <workdir> <phase_id> <attempt>
# Creates directories + a basic session.json + phases.json (1 phase).
# Callers should overwrite specific files for their test scenario.
setup_phase_control() {
    local workdir="$1"
    local phase_id="${2:-phase_1}"
    local attempt="${3:-1}"
    local ctrl="$workdir/.phase_control"

    mkdir -p "$ctrl"/{evidence,verdicts,instructions,delegations,logs,amendments}

    # session.json
    cat > "$ctrl/session.json" <<JSON
{
  "task": "test task",
  "session_id": "test-session-001",
  "status": "IN_PROGRESS",
  "git_head_at_kickoff": "",
  "created_at": "2026-05-30T00:00:00Z"
}
JSON

    # phases.json (1 phase with 3 acceptance_criteria by default)
    cat > "$ctrl/phases.json" <<JSON
{
  "phases": [
    {
      "phase_id": "$phase_id",
      "name": "Test Phase",
      "acceptance_criteria": [
        "Criteria A passes",
        "Criteria B passes",
        "Criteria C passes"
      ]
    }
  ]
}
JSON
}

# ─── Helper: create a complete valid chain for a phase ────────────────────
# This gives hmte-audit-flow.py everything it needs to PASS.
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
  "delegated_at": "2026-05-30T10:00:00Z",
  "leader_session_id": "test-session-001",
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
  "delegated_at": "2026-05-30T10:30:00Z",
  "leader_session_id": "test-session-001",
  "instruction_path": ".phase_control/instructions/${phase_id}_attempt_${attempt}_verifier.json",
  "expected_output_path": ".phase_control/verdicts/${phase_id}_attempt_${attempt}.json",
  "trust_level": "OBSERVED"
}
JSON

    # Command log
    cat > "$ctrl/logs/${phase_id}_attempt_${attempt}.commands.jsonl" <<JSONL
{"phase_id":"$phase_id","attempt":$attempt,"command":"echo 'implementing feature X'","exit_code":0,"runner":"hmte exec","started_at":"2026-05-30T10:00:01Z","ended_at":"2026-05-30T10:00:02Z"}
JSONL

    # Evidence
    cat > "$ctrl/evidence/${phase_id}_attempt_${attempt}.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "status": "completed",
  "timestamp": "2026-05-30T10:05:00Z",
  "changed_files": [],
  "artifact_paths": [],
  "review_only_files": []
}
JSON

    # Verdict (PASS) — includes adversarial_scorecard + independently_verified_files
    cat > "$ctrl/verdicts/${phase_id}_attempt_${attempt}.json" <<JSON
{
  "phase_id": "$phase_id",
  "attempt": $attempt,
  "status": "PASS",
  "timestamp": "2026-05-30T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": ["Criteria A passes", "Criteria B passes", "Criteria C passes"],
    "criteria_failed": [],
    "evidence_paths": [],
    "residual_risks": [],
    "re_verification_conclusion": "All criteria verified"
  },
  "independently_verified_files": ["src/main.py"],
  "blockers": []
}
JSON
}

# ─── Helper: set up src/ tree so phase_gate finds hmte-audit-flow.py ─────
setup_src_tree() {
    local workdir="$1"
    mkdir -p "$workdir/src/skills/hmte/scripts"
    cp "$AUDIT_FLOW" "$workdir/src/skills/hmte/scripts/hmte-audit-flow.py"
    cp "$PHASE_GATE" "$workdir/src/skills/hmte/scripts/phase_gate.sh"
}

# ─── Helper: run a command in a workdir and return its exit code ──────────
# Usage: run_in <workdir> <command...>
# Sets RUN_EXIT_CODE
RUN_EXIT_CODE=0
run_in() {
    local workdir="$1"; shift
    RUN_EXIT_CODE=0
    (cd "$workdir" && "$@") || RUN_EXIT_CODE=$?
}

# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "  HTE v1.4 P0 Hardening — E2E Test Suite"
echo "═══════════════════════════════════════════════════════════════════"
echo "  PROJECT_ROOT=$PROJECT_ROOT"
echo "  FINAL_CHECK=$FINAL_CHECK"
echo "  LINT_INSTRUCTIONS=$LINT_INSTRUCTIONS"
echo "  VERIFY_CLAIMS=$VERIFY_CLAIMS"
echo "  PHASE_GATE=$PHASE_GATE"
echo "  AUDIT_FLOW=$AUDIT_FLOW"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# ─── T1: criteria 被删除 → final-check release FAIL ──────────────────────
echo "─── T1: criteria deletion → final-check --mode release FAIL ───"
T1_DIR="$(mktemp -d)"
T1_EXIT=0

# Set up skeleton
setup_phase_control "$T1_DIR" "phase_1" 1

# goal_lock.json has 3 acceptance_criteria (the "original" locked state)
python3 -c "
import json, hashlib
criteria = ['Criteria A passes', 'Criteria B passes', 'Criteria C passes']
goal_lock = {
    'task': 'test task',
    'phases': [{
        'phase_id': 'phase_1',
        'name': 'Test Phase',
        'acceptance_criteria': criteria,
        'criteria_hash': hashlib.sha256(''.join(criteria).encode()).hexdigest()
    }],
    'created_at': '2026-05-30T00:00:00Z',
    'git_head': ''
}
json.dump(goal_lock, open('$T1_DIR/.phase_control/goal_lock.json','w'), ensure_ascii=False, indent=2)
"

# phases.json now has only 2 acceptance_criteria (one was deleted!)
python3 -c "
import json
data = json.load(open('$T1_DIR/.phase_control/phases.json'))
data['phases'][0]['acceptance_criteria'] = ['Criteria A passes', 'Criteria B passes']
json.dump(data, open('$T1_DIR/.phase_control/phases.json','w'), ensure_ascii=False, indent=2)
"

# Create valid chain so the only failure is criteria mismatch
create_valid_chain "$T1_DIR" "phase_1" 1
setup_src_tree "$T1_DIR"

# Run final-check --mode release; expect exit != 0
run_in "$T1_DIR" bash "$FINAL_CHECK" --mode release
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "T1: criteria deletion → final-check release FAIL"
else
    log_fail "T1: criteria deletion → final-check release FAIL (expected non-zero exit)"
fi
rm -rf "$T1_DIR"

# ─── T2: instruction 出现"只检查格式" → instruction lint release FAIL ───
echo ""
echo "─── T2: weakening phrase '只检查格式' → lint-instructions release FAIL ───"
T2_DIR="$(mktemp -d)"

setup_phase_control "$T2_DIR" "phase_1" 1

# Create an instruction file containing the weakening phrase
cat > "$T2_DIR/.phase_control/instructions/phase_1_attempt_1_worker.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "objective": "只检查格式，不需要实际运行测试"
}
JSON

run_in "$T2_DIR" bash "$LINT_INSTRUCTIONS" --mode release
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "T2: weakening phrase → lint-instructions release FAIL"
else
    log_fail "T2: weakening phrase → lint-instructions release FAIL (expected non-zero exit)"
fi
rm -rf "$T2_DIR"

# ─── T3: changed_files claims README.md but command log doesn't mention it ─
echo ""
echo "─── T3: claimed file not in command log → verify-claims FAIL ───"
T3_DIR="$(mktemp -d)"

setup_phase_control "$T3_DIR" "phase_1" 1

# Evidence claims README.md was changed
cat > "$T3_DIR/.phase_control/evidence/phase_1_attempt_1.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "completed",
  "timestamp": "2026-05-30T10:05:00Z",
  "changed_files": ["README.md"],
  "artifact_paths": [],
  "review_only_files": []
}
JSON

# Command log does NOT mention README.md
cat > "$T3_DIR/.phase_control/logs/phase_1_attempt_1.commands.jsonl" <<JSONL
{"phase_id":"phase_1","attempt":1,"command":"ls -la","exit_code":0,"runner":"hmte exec","started_at":"2026-05-30T10:00:01Z","ended_at":"2026-05-30T10:00:02Z"}
JSONL

# Create the claimed file on disk so test fails for not-in-log, not file-missing
touch "$T3_DIR/README.md"

run_in "$T3_DIR" bash "$VERIFY_CLAIMS"
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "T3: claimed file not in command log → verify-claims FAIL"
else
    log_fail "T3: claimed file not in command log → verify-claims FAIL (expected non-zero exit)"
fi
rm -rf "$T3_DIR"

# ─── T4: PASS verdict missing independently_verified_files → phase_gate FAIL ─
echo ""
echo "─── T4: PASS verdict missing independently_verified_files → phase_gate FAIL ───"
T4_DIR="$(mktemp -d)"

setup_phase_control "$T4_DIR" "phase_1" 1
create_valid_chain "$T4_DIR" "phase_1" 1

# Overwrite the verdict WITHOUT independently_verified_files
cat > "$T4_DIR/.phase_control/verdicts/phase_1_attempt_1.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-05-30T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": ["Criteria A passes", "Criteria B passes", "Criteria C passes"],
    "criteria_failed": [],
    "evidence_paths": [],
    "residual_risks": [],
    "re_verification_conclusion": "All criteria verified"
  },
  "blockers": []
}
JSON

setup_src_tree "$T4_DIR"

run_in "$T4_DIR" bash "$PHASE_GATE" phase_1 --attempt 1
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "T4: missing independently_verified_files → phase_gate FAIL"
else
    log_fail "T4: missing independently_verified_files → phase_gate FAIL (expected non-zero exit)"
fi
rm -rf "$T4_DIR"

# ─── T5: state.json says COMPLETED but phase_gate fails → final-check FAIL ─
echo ""
echo "─── T5: state COMPLETED but missing phase evidence → final-check FAIL ───"
T5_DIR="$(mktemp -d)"

setup_phase_control "$T5_DIR" "phase_1" 1

# Add a second phase to phases.json that has NO evidence/verdict
python3 -c "
import json
data = json.load(open('$T5_DIR/.phase_control/phases.json'))
data['phases'].append({
    'phase_id': 'phase_2',
    'name': 'Missing Phase',
    'acceptance_criteria': ['Must work', 'Must be safe']
})
json.dump(data, open('$T5_DIR/.phase_control/phases.json','w'), ensure_ascii=False, indent=2)
"

# Create valid chain ONLY for phase_1 (NOT for phase_2)
create_valid_chain "$T5_DIR" "phase_1" 1

# state.json claims everything is COMPLETED
cat > "$T5_DIR/.phase_control/session.json" <<JSON
{
  "task": "test task",
  "session_id": "test-session-001",
  "status": "COMPLETED",
  "git_head_at_kickoff": "",
  "created_at": "2026-05-30T00:00:00Z"
}
JSON

setup_src_tree "$T5_DIR"

run_in "$T5_DIR" bash "$FINAL_CHECK"
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "T5: state COMPLETED but missing phase chain → final-check FAIL"
else
    log_fail "T5: state COMPLETED but missing phase chain → final-check FAIL (expected non-zero exit)"
fi
rm -rf "$T5_DIR"

# ─── T6: Leader Jail - project file changed without evidence → FAIL ───────
echo ""
echo "─── T6: Leader Jail - project file changed without evidence → FAIL ───"
T6_DIR="$(mktemp -d)"

setup_phase_control "$T6_DIR" "phase_1" 1
create_valid_chain "$T6_DIR" "phase_1" 1

# Initialize git repo
cd "$T6_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
mkdir -p src
echo "original" > src/main.py
git add .
git commit -q -m "baseline"
BASELINE_COMMIT=$(git rev-parse HEAD)

# Update session.json with baseline
python3 -c "
import json
s = json.load(open('.phase_control/session.json'))
s['git_head_at_kickoff'] = '$BASELINE_COMMIT'
json.dump(s, open('.phase_control/session.json','w'), indent=2)
"

# Create lock.json (Leader Jail activated)
cat > ".phase_control/lock.json" <<JSON
{
  "locked_at": "2026-05-30T10:00:00Z",
  "git_head": "$BASELINE_COMMIT",
  "control_plane": [".phase_control/"]
}
JSON

# Modify project file WITHOUT evidence claiming it
echo "modified by leader" > src/main.py

# Run Leader Jail check
if [ -f "$LEADER_JAIL" ]; then
    run_in "$T6_DIR" bash "$LEADER_JAIL" --mode release
    echo "  → exit_code=$RUN_EXIT_CODE"
    if [ "$RUN_EXIT_CODE" -ne 0 ]; then
        log_pass "T6: project file changed without evidence → Leader Jail FAIL"
    else
        log_fail "T6: project file changed without evidence → Leader Jail FAIL (expected non-zero exit)"
    fi
else
    echo "  ⚠️  SKIP: hmte-leader-jail.sh not found"
fi
rm -rf "$T6_DIR"

# ─── T7: Leader Jail - complete ownership chain → PASS ────────────────────
echo ""
echo "─── T7: Leader Jail - complete ownership chain → PASS ───"
T7_DIR="$(mktemp -d)"

setup_phase_control "$T7_DIR" "phase_1" 1

# Initialize git repo
cd "$T7_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
mkdir -p src
echo "original" > src/main.py
git add .
git commit -q -m "baseline"
BASELINE_COMMIT=$(git rev-parse HEAD)

# Update session.json with baseline
python3 -c "
import json
s = json.load(open('.phase_control/session.json'))
s['git_head_at_kickoff'] = '$BASELINE_COMMIT'
json.dump(s, open('.phase_control/session.json','w'), indent=2)
"

# Create lock.json
cat > ".phase_control/lock.json" <<JSON
{
  "locked_at": "2026-05-30T10:00:00Z",
  "git_head": "$BASELINE_COMMIT",
  "control_plane": [".phase_control/"]
}
JSON

# Modify project file
echo "modified by worker" > src/main.py

# Create complete ownership chain
create_valid_chain "$T7_DIR" "phase_1" 1

# Evidence claims the file
cat > "$T7_DIR/.phase_control/evidence/phase_1_attempt_1.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "completed",
  "timestamp": "2026-05-30T10:05:00Z",
  "changed_files": ["src/main.py"],
  "command_log_path": ".phase_control/logs/phase_1_attempt_1.commands.jsonl"
}
JSON

# Command log mentions the file
cat > "$T7_DIR/.phase_control/logs/phase_1_attempt_1.commands.jsonl" <<'JSONL'
{"phase_id":"phase_1","attempt":1,"command":"patch src/main.py","exit_code":0,"runner":"hmte exec","started_at":"2026-05-30T10:04:00Z","ended_at":"2026-05-30T10:04:01Z"}
JSONL

# Verdict with independently_verified_files
cat > "$T7_DIR/.phase_control/verdicts/phase_1_attempt_1.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-05-30T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": ["Criteria A passes", "Criteria B passes", "Criteria C passes"],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_1_attempt_1.json"],
    "residual_risks": [],
    "re_verification_conclusion": "All criteria verified",
    "independently_verified_files": ["src/main.py"]
  }
}
JSON

setup_src_tree "$T7_DIR"

# Run Leader Jail check
if [ -f "$LEADER_JAIL" ]; then
    run_in "$T7_DIR" bash "$LEADER_JAIL"
    echo "  → exit_code=$RUN_EXIT_CODE"
    if [ "$RUN_EXIT_CODE" -eq 0 ]; then
        log_pass "T7: complete ownership chain → Leader Jail PASS"
    else
        log_fail "T7: complete ownership chain → Leader Jail PASS (expected zero exit)"
    fi
else
    echo "  ⚠️  SKIP: hmte-leader-jail.sh not found"
fi
rm -rf "$T7_DIR"

# ─── T8: Leader Jail - fake_phase not in phases.json → FAIL ───────────────
echo ""
echo "─── T8: Leader Jail - fake_phase not in phases.json → FAIL ───"
T8_DIR="$(mktemp -d)"

setup_phase_control "$T8_DIR" "phase_1" 1

# Initialize git repo
cd "$T8_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
mkdir -p src
echo "original" > src/main.py
git add .
git commit -q -m "baseline"
BASELINE_COMMIT=$(git rev-parse HEAD)

python3 -c "
import json
s = json.load(open('.phase_control/session.json'))
s['git_head_at_kickoff'] = '$BASELINE_COMMIT'
json.dump(s, open('.phase_control/session.json','w'), indent=2)
"

cat > ".phase_control/lock.json" <<JSON
{
  "locked_at": "2026-05-30T10:00:00Z",
  "git_head": "$BASELINE_COMMIT",
  "control_plane": [".phase_control/"]
}
JSON

# Modify project file
echo "modified" > src/main.py

# Evidence from fake_phase (NOT in phases.json)
cat > "$T8_DIR/.phase_control/evidence/fake_phase_attempt_1.json" <<JSON
{
  "phase_id": "fake_phase",
  "attempt": 1,
  "status": "completed",
  "timestamp": "2026-05-30T10:05:00Z",
  "changed_files": ["src/main.py"],
  "command_log_path": ".phase_control/logs/fake_phase_attempt_1.commands.jsonl"
}
JSON

cat > "$T8_DIR/.phase_control/logs/fake_phase_attempt_1.commands.jsonl" <<'JSONL'
{"phase_id":"fake_phase","attempt":1,"command":"patch src/main.py","exit_code":0,"runner":"hmte exec","started_at":"2026-05-30T10:04:00Z","ended_at":"2026-05-30T10:04:01Z"}
JSONL

setup_src_tree "$T8_DIR"

# Run Leader Jail check
if [ -f "$LEADER_JAIL" ]; then
    run_in "$T8_DIR" bash "$LEADER_JAIL" --mode release
    echo "  → exit_code=$RUN_EXIT_CODE"
    if [ "$RUN_EXIT_CODE" -ne 0 ]; then
        log_pass "T8: fake_phase not in phases.json → Leader Jail FAIL"
    else
        log_fail "T8: fake_phase not in phases.json → Leader Jail FAIL (expected non-zero exit)"
    fi
else
    echo "  ⚠️  SKIP: hmte-leader-jail.sh not found"
fi
rm -rf "$T8_DIR"

# ─── T9: Leader Jail - command log doesn't mention changed file → FAIL ────
echo ""
echo "─── T9: Leader Jail - command log doesn't mention changed file → FAIL ───"
T9_DIR="$(mktemp -d)"

setup_phase_control "$T9_DIR" "phase_1" 1

cd "$T9_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
mkdir -p src
echo "original" > src/main.py
git add .
git commit -q -m "baseline"
BASELINE_COMMIT=$(git rev-parse HEAD)

python3 -c "
import json
s = json.load(open('.phase_control/session.json'))
s['git_head_at_kickoff'] = '$BASELINE_COMMIT'
json.dump(s, open('.phase_control/session.json','w'), indent=2)
"

cat > ".phase_control/lock.json" <<JSON
{
  "locked_at": "2026-05-30T10:00:00Z",
  "git_head": "$BASELINE_COMMIT",
  "control_plane": [".phase_control/"]
}
JSON

echo "modified" > src/main.py

create_valid_chain "$T9_DIR" "phase_1" 1

# Evidence claims the file
cat > "$T9_DIR/.phase_control/evidence/phase_1_attempt_1.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "completed",
  "timestamp": "2026-05-30T10:05:00Z",
  "changed_files": ["src/main.py"],
  "command_log_path": ".phase_control/logs/phase_1_attempt_1.commands.jsonl"
}
JSON

# Command log does NOT mention src/main.py
cat > "$T9_DIR/.phase_control/logs/phase_1_attempt_1.commands.jsonl" <<'JSONL'
{"phase_id":"phase_1","attempt":1,"command":"echo hello","exit_code":0,"runner":"hmte exec","started_at":"2026-05-30T10:04:00Z","ended_at":"2026-05-30T10:04:01Z"}
JSONL

cat > "$T9_DIR/.phase_control/verdicts/phase_1_attempt_1.json" <<JSON
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-05-30T10:10:00Z",
  "adversarial_scorecard": {
    "criteria_passed": ["Criteria A passes"],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_1_attempt_1.json"],
    "residual_risks": [],
    "re_verification_conclusion": "Verified",
    "independently_verified_files": ["src/main.py"]
  }
}
JSON

setup_src_tree "$T9_DIR"

# Run Leader Jail check
if [ -f "$LEADER_JAIL" ]; then
    run_in "$T9_DIR" bash "$LEADER_JAIL" --mode release
    echo "  → exit_code=$RUN_EXIT_CODE"
    if [ "$RUN_EXIT_CODE" -ne 0 ]; then
        log_pass "T9: command log doesn't mention changed file → Leader Jail FAIL"
    else
        log_fail "T9: command log doesn't mention changed file → Leader Jail FAIL (expected non-zero exit)"
    fi
else
    echo "  ⚠️  SKIP: hmte-leader-jail.sh not found"
fi
rm -rf "$T9_DIR"

# ─── T10: Goalpost Lock - new phase without amendment → final-check release FAIL ───
echo ""
echo "─── T10: Goalpost Lock - new phase without amendment → final-check release FAIL ───"
T10_DIR="$(mktemp -d)"

setup_phase_control "$T10_DIR" "phase_1" 1
create_valid_chain "$T10_DIR" "phase_1" 1

# Create goal_lock.json with only phase_1
cat > "$T10_DIR/.phase_control/goal_lock.json" <<JSON
{
  "locked_at": "2026-05-30T10:00:00Z",
  "phases": [
    {
      "phase_id": "phase_1",
      "acceptance_criteria": ["Criteria A passes", "Criteria B passes", "Criteria C passes"]
    }
  ]
}
JSON

# Add phase_2 to phases.json WITHOUT amendment
python3 -c "
import json
data = json.load(open('$T10_DIR/.phase_control/phases.json'))
data['phases'].append({
    'phase_id': 'phase_2',
    'name': 'New Phase',
    'acceptance_criteria': ['Easy criterion']
})
json.dump(data, open('$T10_DIR/.phase_control/phases.json','w'), indent=2)
"

setup_src_tree "$T10_DIR"

run_in "$T10_DIR" bash "$FINAL_CHECK" --mode release
echo "  → exit_code=$RUN_EXIT_CODE"
if [ "$RUN_EXIT_CODE" -ne 0 ]; then
    log_pass "T10: new phase without amendment → final-check release FAIL"
else
    log_fail "T10: new phase without amendment → final-check release FAIL (expected non-zero exit)"
fi
rm -rf "$T10_DIR"

# ══════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════
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
