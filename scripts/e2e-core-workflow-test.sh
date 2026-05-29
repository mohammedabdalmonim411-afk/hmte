#!/bin/bash
# E2E Core Workflow Test - covers C1-C6 scenarios
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PASS_COUNT=0
FAIL_COUNT=0

pass() { ((PASS_COUNT++)); echo "✅ PASS: $1"; }
fail() { ((FAIL_COUNT++)); echo "❌ FAIL: $1"; }

# 清理测试环境
cleanup() {
    rm -rf .phase_control/logs .phase_control/evidence .phase_control/verdicts .phase_control/delegations
    mkdir -p .phase_control/{logs,evidence,verdicts,delegations,instructions}
    touch .phase_control/logs/.gitkeep .phase_control/evidence/.gitkeep .phase_control/verdicts/.gitkeep
}
cleanup

# === 辅助函数 ===
make_intent_receipt() {
    local phase_id="$1" attempt="$2" role="$3"
    python3 -c "
import json, datetime
receipt = {
    'phase_id': '$phase_id', 'attempt': $attempt, 'role': '$role',
    'delegated_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'leader_session_id': 'test',
    'instruction_path': '.phase_control/instructions/${phase_id}_${role}_0.json',
    'expected_output_path': '.phase_control/verdicts/${phase_id}_attempt_${attempt}.json',
    'trust_level': 'INTENT_ONLY'
}
with open('.phase_control/delegations/${phase_id}_attempt_${attempt}_${role}.json', 'w') as f:
    json.dump(receipt, f, indent=2)
"
}

make_cmd_log() {
    local phase_id="$1" attempt="$2" cmd="$3"
    bash scripts/hmte-exec.sh "$phase_id" -- $cmd
}

# === C1: phases.json 合法性 ===
test_phases_json() {
    # Create temporary phases.json if not present (it's a runtime file)
    if [ ! -f .phase_control/phases.json ]; then
        echo '{"phases":[{"phase_id":"test","name":"Test","objective":"Validation"}]}' > .phase_control/phases.json
    fi
    if python3 -m json.tool .phase_control/phases.json > /dev/null 2>&1; then
        pass "C1: phases.json is valid JSON"
    else
        fail "C1: phases.json is not valid JSON"
    fi
}

# === C2: hmte exec JSONL 格式 ===
test_hmte_exec_jsonl() {
    bash scripts/hmte-exec.sh c2_test -- echo "hello jsonl"
    local log_file=".phase_control/logs/c2_test_attempt_1.commands.jsonl"
    if [ ! -f "$log_file" ]; then
        fail "C2: JSONL file not created"
        return
    fi
    python3 -c "
import json
from pathlib import Path
p = Path('$log_file')
required = {'phase_id','attempt','command','exit_code','runner','started_at','ended_at','output_tail'}
for i, line in enumerate(p.read_text().splitlines(), 1):
    if not line.strip(): continue
    e = json.loads(line)
    missing = required - set(e)
    if missing:
        print(f'FAIL: line {i} missing {missing}')
        exit(1)
    if e['runner'] != 'hmte exec':
        print(f'FAIL: runner={e[\"runner\"]}')
        exit(1)
    if not isinstance(e['exit_code'], int):
        print(f'FAIL: exit_code not int')
        exit(1)
print('OK')
" && pass "C2: JSONL format valid" || fail "C2: JSONL format invalid"
}

# === C3: audit-flow 完整链路 ===
test_audit_flow() {
    # 1. 生成 command log
    bash scripts/hmte-exec.sh c3_phase -- echo "audit test"

    # 2. 写 evidence
    python3 -c "
import json, datetime
ev = {
    'phase_id': 'c3_phase', 'attempt': 1, 'status': 'completed',
    'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'results': {'test': 'PASS'}, 'files_modified': []
}
with open('.phase_control/evidence/c3_phase_attempt_1.json', 'w') as f:
    json.dump(ev, f, indent=2)
"

    # 3. 写 delegation receipts (worker + verifier)
    # Worker receipt via hmte-write-receipt.sh
    # First create a minimal instruction file
    python3 -c "
import json
instr = {'task_id': 'c3_phase_worker_0', 'role': 'worker', 'goal': 'test'}
with open('.phase_control/instructions/c3_phase_worker_0.json', 'w') as f:
    json.dump(instr, f, indent=2)
"
    bash scripts/hmte-write-receipt.sh c3_phase 1 worker \
        .phase_control/instructions/c3_phase_worker_0.json \
        .phase_control/evidence/c3_phase_attempt_1.json 2>/dev/null || true

    # 写 verifier receipt
    python3 -c "
import json, datetime
receipt = {
    'phase_id': 'c3_phase', 'attempt': 1, 'role': 'verifier',
    'delegated_at': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'leader_session_id': 'test',
    'instruction_path': '.phase_control/instructions/c3_phase_verifier_0.json',
    'expected_output_path': '.phase_control/verdicts/c3_phase_attempt_1.json',
    'trust_level': 'INTENT_ONLY'
}
with open('.phase_control/delegations/c3_phase_attempt_1_verifier.json', 'w') as f:
    json.dump(receipt, f, indent=2)
"

    # 4. 写 verdict (with adversarial_scorecard for PASS)
    python3 -c "
import json, datetime
v = {
    'status': 'PASS', 'phase_id': 'c3_phase', 'attempt': 1,
    'confidence': 'high', 'next_action': 'NEXT_PHASE',
    'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'verification': {'test': 'PASS'},
    'adversarial_scorecard': {
        'criteria_passed': ['all checks'],
        'criteria_failed': [],
        'evidence_paths': ['.phase_control/evidence/c3_phase_attempt_1.json'],
        'residual_risks': [],
        're_verification_conclusion': 'PASS'
    }
}
with open('.phase_control/verdicts/c3_phase_attempt_1.json', 'w') as f:
    json.dump(v, f, indent=2)
"

    # 5. 运行 audit-flow
    if python3 src/skills/hmte/scripts/hmte-audit-flow.py c3_phase 1; then
        pass "C3: audit-flow complete chain"
    else
        fail "C3: audit-flow complete chain"
    fi
}

# === C4: phase_gate --attempt ===
test_phase_gate_attempt() {
    # 复用 C3 的完整链路
    if bash src/skills/hmte/scripts/phase_gate.sh c3_phase --attempt 1; then
        pass "C4: phase_gate with --attempt"
    else
        fail "C4: phase_gate with --attempt"
    fi
}

# === C5b: orchestrator.check_verdict() 真正接入 phase_gate ===
test_orchestrator_rejects_fake_verdict() {
    # 1. 设置完整链路（receipt + cmd_log + evidence + verdict）
    make_intent_receipt "c3_phase" 1 "worker"
    make_intent_receipt "c3_phase" 1 "verifier"
    make_cmd_log "c3_phase" 1 "echo c5b_test"

    # 写一个有效 evidence（audit-flow 要求存在）
    python3 -c "
import json, datetime
ev = {
    'phase_id': 'c3_phase', 'attempt': 1, 'status': 'completed',
    'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'results': {'c5b': 'PASS'}
}
with open('.phase_control/evidence/c3_phase_attempt_1.json', 'w') as f:
    json.dump(ev, f, indent=2)
"

    # 写一个有效 verdict
    python3 -c "
import json, datetime
v = {
    'status': 'PASS', 'phase_id': 'c3_phase', 'attempt': 1,
    'confidence': 'high', 'next_action': 'NEXT_PHASE',
    'timestamp': datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'),
    'adversarial_scorecard': {
        'criteria_passed': [{'criterion': 'test', 'evidence': 'ok'}],
        'criteria_failed': [],
        'evidence_paths': [],
        'residual_risks': ['none'],
        're_verification_conclusion': 'verified'
    }
}
with open('.phase_control/verdicts/c3_phase_attempt_1.json', 'w') as f:
    json.dump(v, f, indent=2)
"

    # 2. 通过 check_verdict 测试（orchestrator 真正使用的路径）
    local result
    result=$(python3 -c "
import sys; sys.path.insert(0, 'src/skills/hmte/scripts')
from orchestrator import Orchestrator
o = Orchestrator('.')
vr = o.check_verdict(
    '.phase_control/verdicts/c3_phase_attempt_1.json',
    phase_id='c3_phase',
    attempt=1
)
print(vr.status)
" 2>/dev/null)

    if [ "$result" = "PASS" ]; then
        pass "C5b: orchestrator.check_verdict() accepts valid verdict with receipt"
    else
        fail "C5b: orchestrator.check_verdict() should accept valid verdict (got: $result)"
    fi

    # 3. 测试 check_verdict 拒绝无 receipt 的 verdict
    rm -f .phase_control/delegations/c3_phase_attempt_1_*.json

    result=$(python3 -c "
import sys; sys.path.insert(0, 'src/skills/hmte/scripts')
from orchestrator import Orchestrator
o = Orchestrator('.')
vr = o.check_verdict(
    '.phase_control/verdicts/c3_phase_attempt_1.json',
    phase_id='c3_phase',
    attempt=1
)
print(vr.status)
" 2>/dev/null)

    if [ "$result" != "PASS" ]; then
        pass "C5b: orchestrator.check_verdict() rejects verdict without receipt"
    else
        fail "C5b: orchestrator.check_verdict() should reject verdict without receipt"
    fi
}

# === C6a: 缺 receipt 被 phase_gate 拒绝 ===
test_phase_gate_no_receipt() {
    rm -f .phase_control/delegations/c3_phase_attempt_1_*.json
    if bash src/skills/hmte/scripts/phase_gate.sh c3_phase --attempt 1 2>/dev/null; then
        fail "C6a: phase_gate should reject when no receipt"
    else
        pass "C6a: phase_gate rejects when no receipt"
    fi
}

# === C6b: audit-flow 拒绝非法 JSON ===
test_audit_flow_rejects_invalid_json() {
    # 写非法 evidence
    echo "not json" > .phase_control/evidence/c3_phase_attempt_1.json
    if python3 src/skills/hmte/scripts/hmte-audit-flow.py c3_phase 1 2>/dev/null; then
        fail "C6b: audit-flow should reject invalid JSON"
    else
        pass "C6b: audit-flow rejects invalid JSON"
    fi
}

# 运行所有测试
test_phases_json
test_hmte_exec_jsonl
test_audit_flow
test_phase_gate_attempt
test_orchestrator_rejects_fake_verdict
test_phase_gate_no_receipt
test_audit_flow_rejects_invalid_json

# 清理
cleanup

echo ""
echo "=========================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "=========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
