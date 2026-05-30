#!/usr/bin/env bash
set -euo pipefail

# Phase 2 Acceptance Test
# Tests final_audit with phase_gate

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

CTRL=".phase_control"
PHASE_ID="final_audit"
ATTEMPT=1

echo "=== Phase 2 Acceptance Test ==="
echo ""

# Helper function to create complete 7-file chain
make_final_audit_chain() {
    local phase_id="$1"
    local attempt="$2"
    local verdict_status="$3"
    
    echo "Creating 7-file chain for $phase_id attempt $attempt with status $verdict_status"
    
    # 1. Worker instruction
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
instr = {
    "phase_id": phase_id,
    "attempt": attempt,
    "role": "worker",
    "assigned_to": "phase-executor",
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "objective": "Execute final audit checks",
    "output_path": f".phase_control/evidence/{phase_id}_attempt_{attempt}.json"
}
Path(ctrl, "instructions", f"{phase_id}_attempt_{attempt}_worker.json").write_text(
    json.dumps(instr, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY
    
    # 2. Verifier instruction
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
instr = {
    "phase_id": phase_id,
    "attempt": attempt,
    "role": "verifier",
    "assigned_to": "release-auditor",
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "objective": "Audit final_audit evidence",
    "output_path": f".phase_control/verdicts/{phase_id}_attempt_{attempt}.json"
}
Path(ctrl, "instructions", f"{phase_id}_attempt_{attempt}_verifier.json").write_text(
    json.dumps(instr, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY
    
    # 3. Worker receipt
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
now = datetime.now(timezone.utc)
receipt = {
    "phase_id": phase_id,
    "attempt": attempt,
    "role": "worker",
    "trust_level": "INTENT_ONLY",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_worker.json",
    "expected_output_path": f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
    "delegated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "created_at": now.strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_worker.json").write_text(
    json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY
    
    # 4. Verifier receipt
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
now = datetime.now(timezone.utc)
receipt = {
    "phase_id": phase_id,
    "attempt": attempt,
    "role": "verifier",
    "trust_level": "INTENT_ONLY",
    "delegation_method": "delegate_task",
    "leader_instruction_path": f".phase_control/instructions/{phase_id}_attempt_{attempt}_verifier.json",
    "expected_output_path": f".phase_control/verdicts/{phase_id}_attempt_{attempt}.json",
    "delegated_at": (now + timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "created_at": (now + timedelta(seconds=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
}
Path(ctrl, "delegations", f"{phase_id}_attempt_{attempt}_verifier.json").write_text(
    json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY
    
    # 5. Command log (create with at least one entry)
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
entry = {
    "phase_id": phase_id,
    "attempt": attempt,
    "command": "echo 'final audit checks'",
    "exit_code": 0,
    "runner": "hmte exec",
    "started_at": now,
    "ended_at": now
}
Path(ctrl, "logs", f"{phase_id}_attempt_{attempt}.commands.jsonl").write_text(
    json.dumps(entry, ensure_ascii=False) + "\n", encoding="utf-8"
)
PY
    
    # 6. Evidence
    python3 - "$CTRL" "$phase_id" "$attempt" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

ctrl, phase_id, attempt = sys.argv[1], sys.argv[2], int(sys.argv[3])
now = datetime.now(timezone.utc) + timedelta(seconds=2)
evidence = {
    "phase_id": phase_id,
    "attempt": attempt,
    "status": "completed",
    "timestamp": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "checks_performed": [
        "原始目标完成检查",
        "所有 phase PASS 检查",
        "完整链路验证",
        "phase_gate 验证",
        "git diff 基线对比",
        "文档一致性检查",
        "旧协议残留检查",
        "全量测试执行",
        "风险和缺口汇总",
        "交付条件评估"
    ]
}
Path(ctrl, "evidence", f"{phase_id}_attempt_{attempt}.json").write_text(
    json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY
    
    # 7. Verdict
    python3 - "$CTRL" "$phase_id" "$attempt" "$verdict_status" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

ctrl, phase_id, attempt, status = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
now = datetime.now(timezone.utc) + timedelta(seconds=3)
verdict = {
    "status": status,
    "phase_id": phase_id,
    "attempt": attempt,
    "timestamp": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "scope": "whole_project",
    "adversarial_scorecard": {
        "criteria_passed": [
            "原始目标完成",
            "所有 phase PASS",
            "完整链路存在",
            "phase_gate 全通过",
            "git diff 无意外",
            "文档口径一致",
            "无旧协议残留",
            "全量测试通过",
            "风险可控",
            "满足交付条件"
        ] if status == "PASS" else [],
        "criteria_failed": [] if status == "PASS" else ["Some criteria failed"],
        "global_conflicts": [],
        "evidence_paths": [
            f".phase_control/evidence/{phase_id}_attempt_{attempt}.json",
            f".phase_control/logs/{phase_id}_attempt_{attempt}.commands.jsonl"
        ],
        "residual_risks": [],
        "re_verification_conclusion": "Ready for release" if status == "PASS" else "Needs fixes"
    },
    "next_action": "RELEASE" if status == "PASS" else "RETURN_TO_LEADER"
}
Path(ctrl, "verdicts", f"{phase_id}_attempt_{attempt}.json").write_text(
    json.dumps(verdict, ensure_ascii=False, indent=2), encoding="utf-8"
)
PY
    
    echo "✅ Created 7-file chain for $phase_id"
}

# Clean up any existing final_audit files
echo "Cleaning up existing final_audit files..."
rm -f "$CTRL/instructions/final_audit_attempt_1_worker.json"
rm -f "$CTRL/instructions/final_audit_attempt_1_verifier.json"
rm -f "$CTRL/delegations/final_audit_attempt_1_worker.json"
rm -f "$CTRL/delegations/final_audit_attempt_1_verifier.json"
rm -f "$CTRL/logs/final_audit_attempt_1.commands.jsonl"
rm -f "$CTRL/evidence/final_audit_attempt_1.json"
rm -f "$CTRL/verdicts/final_audit_attempt_1.json"

# Test 1: PASS verdict should pass phase_gate
echo ""
echo "Test 1: final_audit with PASS verdict"
make_final_audit_chain "$PHASE_ID" "$ATTEMPT" "PASS"

if bash src/skills/hmte/scripts/phase_gate.sh "$PHASE_ID" --attempt "$ATTEMPT" 2>/dev/null; then
    echo "✅ PASS: phase_gate accepted PASS verdict"
else
    echo "❌ FAIL: phase_gate rejected PASS verdict"
    exit 1
fi

# Test 2: evidence_paths not empty
echo ""
echo "Test 2: evidence_paths not empty"
python3 -c "
import json
v = json.load(open('.phase_control/verdicts/final_audit_attempt_1.json'))
paths = v['adversarial_scorecard']['evidence_paths']
assert len(paths) >= 2, f'Expected at least 2 paths, got {len(paths)}'
assert '.phase_control/evidence/final_audit_attempt_1.json' in paths
assert '.phase_control/logs/final_audit_attempt_1.commands.jsonl' in paths
print('✅ PASS: evidence_paths contains required paths')
"

# Test 3: FAIL verdict should fail phase_gate
echo ""
echo "Test 3: final_audit with FAIL verdict"
make_final_audit_chain "$PHASE_ID" "$ATTEMPT" "FAIL"

if bash src/skills/hmte/scripts/phase_gate.sh "$PHASE_ID" --attempt "$ATTEMPT" 2>/dev/null; then
    echo "❌ FAIL: phase_gate should reject FAIL verdict"
    exit 1
else
    echo "✅ PASS: phase_gate correctly rejected FAIL verdict"
fi

# Test 4: Verify all 7 files exist
echo ""
echo "Test 4: Verify 7-file chain completeness"
required_files=(
    "$CTRL/instructions/${PHASE_ID}_attempt_${ATTEMPT}_worker.json"
    "$CTRL/instructions/${PHASE_ID}_attempt_${ATTEMPT}_verifier.json"
    "$CTRL/delegations/${PHASE_ID}_attempt_${ATTEMPT}_worker.json"
    "$CTRL/delegations/${PHASE_ID}_attempt_${ATTEMPT}_verifier.json"
    "$CTRL/logs/${PHASE_ID}_attempt_${ATTEMPT}.commands.jsonl"
    "$CTRL/evidence/${PHASE_ID}_attempt_${ATTEMPT}.json"
    "$CTRL/verdicts/${PHASE_ID}_attempt_${ATTEMPT}.json"
)

all_exist=true
for f in "${required_files[@]}"; do
    if [ ! -f "$f" ]; then
        echo "❌ Missing: $f"
        all_exist=false
    fi
done

if [ "$all_exist" = true ]; then
    echo "✅ PASS: All 7 files exist"
else
    echo "❌ FAIL: Some files missing"
    exit 1
fi

# Test 5: Verify no .evidence. or .verdict. infix
echo ""
echo "Test 5: Verify no forbidden naming conventions"
if find "$CTRL" -name "*.evidence.json" -o -name "*.verdict.json" 2>/dev/null | grep .; then
    echo "❌ FAIL: Found files with .evidence. or .verdict. infix"
    exit 1
else
    echo "✅ PASS: No forbidden naming conventions found"
fi

# Test 6: Verify next_action field exists
echo ""
echo "Test 6: Verify next_action field"
python3 -c "
import json
v = json.load(open('.phase_control/verdicts/final_audit_attempt_1.json'))
assert 'next_action' in v, 'next_action field missing'
assert v['next_action'] in ['RELEASE', 'RETURN_TO_LEADER', 'ESCALATE'], f'Invalid next_action: {v[\"next_action\"]}'
print(f'✅ PASS: next_action = {v[\"next_action\"]}')
"

echo ""
echo "=== Phase 2 Acceptance Tests: ALL PASSED ==="
