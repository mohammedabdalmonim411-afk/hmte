#!/usr/bin/env bash
# E2E Lifecycle Test - covers kickoff → phases → final_audit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure E2E tests run independently of local Hermes installation
export HMTE_SKILL_DIR="$PROJECT_ROOT/src/skills/hmte"

# Create isolated test environment
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "🔧 Setting up isolated test environment: $TMPDIR"

# Copy only necessary files (not .git)
cp -a "$PROJECT_ROOT/scripts" "$TMPDIR/scripts"
cp -a "$PROJECT_ROOT/src" "$TMPDIR/src"
for f in README.md HERMES.md CONTRIBUTING.md CHANGELOG.md LICENSE; do
    [ -f "$PROJECT_ROOT/$f" ] && cp -a "$PROJECT_ROOT/$f" "$TMPDIR/$f"
done

# Create .phase_control structure
mkdir -p "$TMPDIR/.phase_control"
RUNTIME_SUBDIRS="instructions evidence verdicts logs delegations errors pids traces"
for d in $RUNTIME_SUBDIRS; do
    mkdir -p "$TMPDIR/.phase_control/$d"
    touch "$TMPDIR/.phase_control/$d/.gitkeep"
done

# Initialize temporary git repo with local identity
cd "$TMPDIR"
GIT_AVAILABLE=false
if git init -q 2>/dev/null; then
    git config user.email "hte-test@example.local"
    git config user.name "TAF Test"
    git add -A 2>/dev/null || true
    git commit -m "init" --allow-empty -q 2>/dev/null || true
    GIT_AVAILABLE=true
    echo "✅ Git initialized"
else
    echo "⚠️  Git not available, some tests degraded"
fi

# Set up paths
CTRL="$TMPDIR/.phase_control"
SCRIPTS="$TMPDIR/scripts"
SKILL="$TMPDIR/src/skills/hmte"

# Test counters
PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "✅ PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "❌ FAIL: $1"; }

# Unified reset function
reset_runtime() {
    local dir
    for dir in $RUNTIME_SUBDIRS; do
        find "$CTRL/$dir" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
    done
    rm -f "$CTRL/state.json" "$CTRL/session.json" "$CTRL/phases.json"
    rm -rf "$TMPDIR/.phase_control_archive/"
}

# Helper: make_final_audit_chain
# Args: $1=phase_id $2=attempt $3=verdict_status $4=receipt_type
make_final_audit_chain() {
    local phase_id="$1"
    local attempt="$2"
    local verdict_status="$3"
    local receipt_type="${4:-NORMAL}"
    
    # 1. Worker instruction
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
instr = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "worker",
    "objective": f"Execute {phase_id}",
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "instructions", f"{phase_id}_attempt_{attempt}_worker.json").write_text(
    json.dumps(instr, indent=2), encoding="utf-8"
)
PY

    # 2. Verifier instruction
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
instr = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "verifier",
    "objective": f"Verify {phase_id}",
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "instructions", f"{phase_id}_attempt_{attempt}_verifier.json").write_text(
    json.dumps(instr, indent=2), encoding="utf-8"
)
PY

    # 3. Worker receipt
    if [ "$receipt_type" = "OBSERVED_NO_TRACE" ]; then
        python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
receipt = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "worker",
    "delegation_trust_level": "OBSERVED",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_worker.json",
    "expected_output_path": f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
    "tool_call_trace_path": None,
    "observed_delegate_task_id": None,
    "timestamp": ts,
    "delegated_at": ts
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_worker.json").write_text(
    json.dumps(receipt, indent=2), encoding="utf-8"
)
PY
    else
        python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
receipt = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "worker",
    "delegation_trust_level": "INTENT_ONLY",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_worker.json",
    "expected_output_path": f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
    "tool_call_trace_path": None,
    "observed_delegate_task_id": None,
    "timestamp": ts,
    "delegated_at": ts
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_worker.json").write_text(
    json.dumps(receipt, indent=2), encoding="utf-8"
)
PY
    fi

    # 4. Verifier receipt
    if [ "$receipt_type" = "OBSERVED_NO_TRACE" ]; then
        python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
receipt = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "verifier",
    "delegation_trust_level": "OBSERVED",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_verifier.json",
    "expected_output_path": f".phase_control/verdicts/{phase_id}_attempt_{attempt}.json",
    "tool_call_trace_path": None,
    "observed_delegate_task_id": None,
    "timestamp": ts,
    "delegated_at": ts
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_verifier.json").write_text(
    json.dumps(receipt, indent=2), encoding="utf-8"
)
PY
    else
        python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
receipt = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "verifier",
    "delegation_trust_level": "INTENT_ONLY",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_verifier.json",
    "expected_output_path": f".phase_control/verdicts/{phase_id}_attempt_{attempt}.json",
    "tool_call_trace_path": None,
    "observed_delegate_task_id": None,
    "timestamp": ts,
    "delegated_at": ts
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_verifier.json").write_text(
    json.dumps(receipt, indent=2), encoding="utf-8"
)
PY
    fi

    # 5. Command log (via hmte-exec)
    bash "$SCRIPTS/hmte-exec.sh" "$phase_id" --attempt "$attempt" -- echo "test command"

    # 6. Evidence
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
evidence = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "status": "completed",
    "generated_at": generated_at,
    "timestamp": generated_at,
    "results": {"test": "PASS"},
    "files_modified": [],
    "changed_files": ["README.md"],
    "command_log_path": f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl"
}
if phase_id == "final_audit":
    try:
        phases = json.loads(Path(ctrl, "phases.json").read_text(encoding="utf-8"))
        evidence["covered_phases"] = [
            p.get("phase_id") or p.get("id")
            for p in phases.get("phases", [])
            if (p.get("phase_id") or p.get("id"))
        ]
    except Exception:
        evidence["covered_phases"] = []
Path(ctrl, "evidence", f"{phase_id}_attempt_{attempt}.json").write_text(
    json.dumps(evidence, indent=2), encoding="utf-8"
)
PY

    # 7. Verdict
    python3 - "$CTRL" "$phase_id" "$attempt" "$verdict_status" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl, phase_id, attempt, status = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
verdict = {
    "status": status,
    "phase_id": phase_id,
    "attempt": int(attempt),
    "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "confidence": "high",
    "next_action": "RELEASE" if status == "PASS" else "RETURN_TO_LEADER",
    "adversarial_scorecard": {
        "criteria_passed": [{"criterion": "test execution completed", "evidence": f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl shows command exit_code=0"}] if status == "PASS" else [],
        "criteria_failed": [] if status == "PASS" else [{"criterion": "test execution failed", "reason": "command returned non-zero exit code"}],
        "evidence_paths": [
            f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
            f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl"
        ],
        "residual_risks": ["none"],
        "re_verification_conclusion": f"{status} verdict after reviewing command log and evidence bundle - all acceptance criteria validated" if status == "PASS" else f"{status} verdict - execution failed validation",
        "independently_verified_files": ["README.md"],
        "command_log_checked": True,
        "diff_checked": True,
        "evidence_consistency_checked": True,
        "verification_method": "manual_review",
        "risk_disposition": [{"risk": "none identified in test phase", "disposition": "accepted", "reason": "test environment with no production impact"}]
    }
}
Path(ctrl, "verdicts", f"{phase_id}_attempt_{attempt}.json").write_text(
    json.dumps(verdict, indent=2), encoding="utf-8"
)
PY
}

echo ""
echo "=========================================="
echo "Running E2E Lifecycle Tests"
echo "=========================================="
echo ""

# === L1: Kickoff creates startup files ===
echo "--- L1: Kickoff creates startup files ---"
reset_runtime
if bash "$SCRIPTS/hmte-kickoff.sh" "L1 test task" >/dev/null 2>&1; then
    if [ -f "$CTRL/session.json" ] && [ -f "$CTRL/instructions/leader_kickoff.json" ]; then
        # Validate session.json structure
        if python3 -c "import json; s=json.load(open('$CTRL/session.json')); assert s['status']=='KICKED_OFF'; assert 'git_head_at_kickoff' in s; assert 'git_status_at_kickoff' in s" 2>/dev/null; then
            pass "L1: Kickoff creates valid startup files"
        else
            fail "L1: session.json structure invalid"
        fi
    else
        fail "L1: Required files not created"
    fi
else
    fail "L1: Kickoff failed"
fi

# === L2: Audit Start unplanned state (no phases.json) ===
echo ""
echo "--- L2: Audit Start unplanned state ---"
reset_runtime
bash "$SCRIPTS/hmte-kickoff.sh" "L2 test task" >/dev/null 2>&1
result=$(bash "$SCRIPTS/hmte-audit-start.sh" 2>/dev/null || echo '{}')
status=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
if [ "$status" = "KICKED_OFF" ]; then
    pass "L2: Audit Start returns KICKED_OFF without phases.json"
else
    fail "L2: Expected KICKED_OFF, got: $status"
fi

# === L3: Audit Start delegatable state ===
echo ""
echo "--- L3: Audit Start delegatable state ---"
reset_runtime
bash "$SCRIPTS/hmte-kickoff.sh" "L3 test task" >/dev/null 2>&1
# Add phases.json
echo '{"phases":[{"phase_id":"test_phase","name":"Test","objective":"Test phase"}]}' > "$CTRL/phases.json"
# Add worker instruction
python3 - "$CTRL" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path
ctrl = Path(sys.argv[1])
instr = {
    "phase_id": "test_phase",
    "attempt": 1,
    "role": "worker",
    "objective": "Test",
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
}
(ctrl / "instructions" / "test_phase_attempt_1_worker.json").write_text(
    json.dumps(instr, indent=2), encoding="utf-8"
)
PY
result=$(bash "$SCRIPTS/hmte-audit-start.sh" 2>/dev/null || echo '{}')
status=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
if [ "$status" = "READY_FOR_WORKER" ]; then
    pass "L3: Audit Start returns READY_FOR_WORKER"
else
    fail "L3: Expected READY_FOR_WORKER, got: $status"
fi

# === L4: Final Audit PASS ===
echo ""
echo "--- L4: Final Audit PASS ---"
reset_runtime
make_final_audit_chain "final_audit" 1 "PASS" "NORMAL"
# Verify all 7 files exist
files_exist=true
for f in \
    "$CTRL/instructions/final_audit_attempt_1_worker.json" \
    "$CTRL/instructions/final_audit_attempt_1_verifier.json" \
    "$CTRL/delegations/final_audit_attempt_1_worker.json" \
    "$CTRL/delegations/final_audit_attempt_1_verifier.json" \
    "$CTRL/logs/final_audit_attempt_1.commands.jsonl" \
    "$CTRL/evidence/final_audit_attempt_1.json" \
    "$CTRL/verdicts/final_audit_attempt_1.json"; do
    if [ ! -f "$f" ]; then
        files_exist=false
        fail "L4: Missing file: $f"
    fi
done

if [ "$files_exist" = true ]; then
    # Verify evidence_paths non-empty
    ep_count=$(python3 -c "import json; v=json.load(open('$CTRL/verdicts/final_audit_attempt_1.json')); print(len(v['adversarial_scorecard']['evidence_paths']))" 2>/dev/null || echo "0")
    if [ "$ep_count" -ge 2 ]; then
        # Run phase_gate
        if bash "$SKILL/scripts/phase_gate.sh" final_audit --attempt 1 >/dev/null 2>&1; then
            pass "L4: Final Audit PASS with complete 7-file chain"
        else
            fail "L4: phase_gate rejected PASS verdict"
        fi
    else
        fail "L4: evidence_paths empty or insufficient"
    fi
fi

# === L5: Final Audit FAIL ===
echo ""
echo "--- L5: Final Audit FAIL ---"
reset_runtime
make_final_audit_chain "final_audit" 1 "FAIL" "NORMAL"
# Verify all 7 files exist
files_exist=true
for f in \
    "$CTRL/instructions/final_audit_attempt_1_worker.json" \
    "$CTRL/instructions/final_audit_attempt_1_verifier.json" \
    "$CTRL/delegations/final_audit_attempt_1_worker.json" \
    "$CTRL/delegations/final_audit_attempt_1_verifier.json" \
    "$CTRL/logs/final_audit_attempt_1.commands.jsonl" \
    "$CTRL/evidence/final_audit_attempt_1.json" \
    "$CTRL/verdicts/final_audit_attempt_1.json"; do
    if [ ! -f "$f" ]; then
        files_exist=false
        fail "L5: Missing file: $f"
    fi
done

if [ "$files_exist" = true ]; then
    # Run phase_gate - should reject FAIL
    if bash "$SKILL/scripts/phase_gate.sh" final_audit --attempt 1 >/dev/null 2>&1; then
        fail "L5: phase_gate should reject FAIL verdict"
    else
        pass "L5: Final Audit FAIL correctly rejected, all 7 files exist"
    fi
fi

# === L6a: Old receipt compatibility (trust_level) ===
echo ""
echo "--- L6a: Old receipt compatibility ---"
reset_runtime
P="test_l6a"
A=1
make_final_audit_chain "$P" "$A" "PASS" "NORMAL"
# Replace with old-style receipt (trust_level instead of delegation_trust_level)
python3 - "$CTRL" "$P" "$A" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], sys.argv[3]
evidence_path = Path(ctrl, "evidence", f"{phase_id}_attempt_{attempt}.json")
evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
evidence_ts = datetime.strptime(evidence["timestamp"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
receipt_ts = (evidence_ts - timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
receipt = {
    "phase_id": phase_id,
    "attempt": int(attempt),
    "role": "worker",
    "trust_level": "INTENT_ONLY",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_worker.json",
    "expected_output_path": f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
    "delegated_at": receipt_ts
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_worker.json").write_text(
    json.dumps(receipt, indent=2), encoding="utf-8"
)
PY
# Run audit-flow with debugging
result=$(python3 "$SKILL/scripts/hmte-audit-flow.py" "$P" "$A" --json 2>&1 || echo '{}')
overall=$(echo "$result" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('overall','FAIL'))" 2>/dev/null || echo "FAIL")
if [ "$overall" != "PASS" ]; then
    echo "DEBUG: audit-flow output: $result" >&2
fi
if [ "$overall" = "PASS" ]; then
    pass "L6a: Old receipt (trust_level) compatible"
else
    fail "L6a: Old receipt not compatible, overall=$overall"
fi

# === L6b: New receipt compatibility (delegation_trust_level) ===
echo ""
echo "--- L6b: New receipt compatibility ---"
reset_runtime
P="test_l6b"
A=1
make_final_audit_chain "$P" "$A" "PASS" "NORMAL"
# Already uses delegation_trust_level
result=$(python3 "$SKILL/scripts/hmte-audit-flow.py" "$P" "$A" --json 2>/dev/null || echo '{}')
overall=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('overall','FAIL'))" 2>/dev/null || echo "FAIL")
if [ "$overall" = "PASS" ]; then
    pass "L6b: New receipt (delegation_trust_level) compatible"
else
    fail "L6b: New receipt not compatible, overall=$overall"
fi

# === L6c: OBSERVED without trace (never OBSERVED+PASS) ===
echo ""
echo "--- L6c: OBSERVED without trace ---"
reset_runtime
P="test_l6c"
A=1
make_final_audit_chain "$P" "$A" "PASS" "OBSERVED_NO_TRACE"
# Run audit-flow
result=$(python3 "$SKILL/scripts/hmte-audit-flow.py" "$P" "$A" --json 2>/dev/null || echo '{}')
overall=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('overall','FAIL'))" 2>/dev/null || echo "FAIL")
trust=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin).get('trust_level','NONE'))" 2>/dev/null || echo "NONE")

# Core assertion: MUST NOT be OBSERVED+PASS
if [ "$trust" = "OBSERVED" ] && [ "$overall" = "PASS" ]; then
    fail "L6c: CRITICAL - OBSERVED without trace passed as OBSERVED (forbidden)"
else
    pass "L6c: OBSERVED without trace correctly degraded (not OBSERVED+PASS)"
fi

# === Kickoff residual rejection for all 8 directories ===
echo ""
echo "--- Kickoff residual rejection tests ---"
for subdir in $RUNTIME_SUBDIRS; do
    reset_runtime
    touch "$CTRL/$subdir/test_marker.tmp"
    if bash "$SCRIPTS/hmte-kickoff.sh" "test" >/dev/null 2>&1; then
        fail "Kickoff should reject residual in ${subdir}"
    else
        pass "Kickoff correctly rejects residual in ${subdir}"
    fi
    rm -f "$CTRL/$subdir/test_marker.tmp"
done

# === Summary ===
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "✅ PASS: $PASS_COUNT"
echo "❌ FAIL: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "💥 Some tests failed"
    exit 1
fi
