#!/bin/bash
# E2E Core Workflow Test - covers C1-C6 scenarios
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Ensure E2E tests run independently of local Hermes installation
export HMTE_SKILL_DIR="$PROJECT_ROOT/src/skills/hmte"

PASS_COUNT=0
FAIL_COUNT=0

# Incrementing deterministic timestamp helper (avoids timeline flake)
_TS_NEXT=0
_ts() { _TS_NEXT=$((_TS_NEXT + 1)); printf "2026-01-01T00:00:%02dZ" $_TS_NEXT; }

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "✅ PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "❌ FAIL: $1"; }

# 清理测试环境
cleanup() {
    rm -rf .phase_control/logs .phase_control/evidence .phase_control/verdicts .phase_control/delegations .phase_control/errors .phase_control/pids .phase_control/traces
    rm -f .phase_control/run_ledger.jsonl .phase_control/session.json .phase_control/phases.json .phase_control/state.json
    mkdir -p .phase_control/{logs,evidence,verdicts,delegations,instructions,errors,pids,traces,state,amendments}
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
    'delegated_at': '$(_ts)',
    'timestamp': '$(_ts)',
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

    # 2. 写 delegation receipts FIRST (timeline: receipt ≤ evidence ≤ verdict)
    # Worker receipt — write directly with fixed timestamp
    python3 -c "
import json
receipt = {
    'phase_id': 'c3_phase', 'attempt': 1, 'role': 'worker',
    'delegated_at': '$(_ts)',
    'leader_session_id': 'test',
    'instruction_path': '.phase_control/instructions/c3_phase_worker_0.json',
    'expected_output_path': '.phase_control/evidence/c3_phase_attempt_1.json',
    'trust_level': 'INTENT_ONLY'
}
with open('.phase_control/delegations/c3_phase_attempt_1_worker.json', 'w') as f:
    json.dump(receipt, f, indent=2)
"

    # 写 verifier receipt
    python3 -c "
import json
receipt = {
    'phase_id': 'c3_phase', 'attempt': 1, 'role': 'verifier',
    'delegated_at': '$(_ts)',
    'leader_session_id': 'test',
    'instruction_path': '.phase_control/instructions/c3_phase_verifier_0.json',
    'expected_output_path': '.phase_control/verdicts/c3_phase_attempt_1.json',
    'trust_level': 'INTENT_ONLY'
}
with open('.phase_control/delegations/c3_phase_attempt_1_verifier.json', 'w') as f:
    json.dump(receipt, f, indent=2)
"

    # 3. 写 evidence (after receipts so timestamp is ≥ receipt time)
    python3 -c "
import json
ev = {
    'phase_id': 'c3_phase', 'attempt': 1, 'status': 'completed',
    'timestamp': '$(_ts)',
    'results': {'test': 'PASS'}, 'files_modified': [], 'command_log_path': '.phase_control/logs/c3_phase_attempt_1.commands.jsonl'
}
with open('.phase_control/evidence/c3_phase_attempt_1.json', 'w') as f:
    json.dump(ev, f, indent=2)
"

    # 4. 写 verdict (with adversarial_scorecard for PASS)
    python3 -c "
import json, datetime
v = {
    'status': 'PASS', 'phase_id': 'c3_phase', 'attempt': 1,
    'confidence': 'high', 'next_action': 'NEXT_PHASE',
    'timestamp': '$(_ts)',
    'verification': {'test': 'PASS'},
    'adversarial_scorecard': {
        'criteria_passed': [{'criterion': 'test', 'evidence': 'test execution completed successfully'}],
        'criteria_failed': [],
        'evidence_paths': ['.phase_control/evidence/c3_phase_attempt_1.json', '.phase_control/logs/c3_phase_attempt_1.commands.jsonl'],
        'residual_risks': [],
        're_verification_conclusion': 'All criteria verified through code review and test execution',
        'independently_verified_files': ['README.md'],
        'command_log_checked': True,
        'diff_checked': True,
        'evidence_consistency_checked': True,
        'verification_method': 'code_review',
        'risk_disposition': []
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
    'timestamp': '$(_ts)',
    'results': {'c5b': 'PASS'}, 'command_log_path': '.phase_control/logs/c3_phase_attempt_1.commands.jsonl'
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
    'timestamp': '$(_ts)',
    'adversarial_scorecard': {
        'criteria_passed': [{'criterion': 'test', 'evidence': 'test execution completed successfully'}],
        'criteria_failed': [],
        'evidence_paths': ['.phase_control/evidence/c3_phase_attempt_1.json', '.phase_control/logs/c3_phase_attempt_1.commands.jsonl'],
        'residual_risks': ['none'],
        're_verification_conclusion': 'All criteria verified through code review and test execution',
        'independently_verified_files': ['README.md'],
        'command_log_checked': True,
        'diff_checked': True,
        'evidence_consistency_checked': True,
        'verification_method': 'code_review',
        'risk_disposition': []
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

# === C7: Run Ledger 真实闭环 ===
test_run_ledger_closure() {
    local phase_id="ledger_phase"

    # 最小运行态文件，供 hmte-status / hmte-doctor 读取
    python3 - <<'PY'
import json
from pathlib import Path
pc = Path('.phase_control')
pc.joinpath('session.json').write_text(json.dumps({
    'workflow': 'TAF',
    'mode': 'file-instruction',
    'task': 'run ledger closure',
    'status': 'RUNNING',
    'created_at': '2026-01-01T00:00:00Z'
}, indent=2))
pc.joinpath('phases.json').write_text(json.dumps({
    'phases': [{
        'phase_id': 'ledger_phase',
        'name': 'Ledger Phase',
        'objective': 'Verify run ledger closure'
    }]
}, indent=2))
pc.joinpath('state.json').write_text(json.dumps({
    'session_id': 'ledger-session',
    'mode': 'file-instruction',
    'current_phase': 'ledger_phase',
    'phase_status': 'RUNNING',
    'started_at': '2026-01-01T00:00:00Z'
}, indent=2))
PY

    make_intent_receipt "$phase_id" 1 "worker"
    make_intent_receipt "$phase_id" 1 "verifier"
    make_cmd_log "$phase_id" 1 "echo ledger closure"

    python3 - <<'PY'
import json
from pathlib import Path
phase_id = 'ledger_phase'
pc = Path('.phase_control')
evidence = {
    'phase_id': phase_id,
    'attempt': 1,
    'status': 'completed',
    'timestamp': '2026-01-01T00:00:07Z',
    'results': {'ledger': 'PASS'},
    'changed_files': [],
    'unresolved_risks': [],
    'command_log_path': f'.phase_control/logs/{phase_id}_attempt_1.commands.jsonl',
}
pc.joinpath(f'evidence/{phase_id}_attempt_1.json').write_text(json.dumps(evidence, indent=2))
verdict = {
    'status': 'PASS',
    'phase_id': phase_id,
    'attempt': 1,
    'confidence': 'high',
    'next_action': 'NEXT_PHASE',
    'timestamp': '2026-01-01T00:00:08Z',
    'adversarial_scorecard': {
        'criteria_passed': [{
            'criterion': 'run ledger written',
            'evidence': 'check_verdict() writes gate_result to run_ledger.jsonl'
        }],
        'criteria_failed': [],
        'evidence_paths': [
            f'.phase_control/evidence/{phase_id}_attempt_1.json',
            f'.phase_control/logs/{phase_id}_attempt_1.commands.jsonl'
        ],
        'residual_risks': [],
        're_verification_conclusion': 'Run Ledger path is observable and valid',
        'independently_verified_files': ['scripts/hmte-status.sh'],
        'command_log_checked': True,
        'diff_checked': True,
        'evidence_consistency_checked': True,
        'verification_method': 'code_review',
        'risk_disposition': []
    }
}
pc.joinpath(f'verdicts/{phase_id}_attempt_1.json').write_text(json.dumps(verdict, indent=2))
PY

    if python3 - <<'PY'
import json
import sys
from pathlib import Path
sys.path.insert(0, 'src/skills/hmte/scripts')
from orchestrator import Orchestrator
o = Orchestrator('.')
vr = o.check_verdict(
    '.phase_control/verdicts/ledger_phase_attempt_1.json',
    phase_id='ledger_phase',
    attempt=1,
)
if vr.status != 'PASS':
    print(f'FAIL: orchestrator.check_verdict() returned {vr.status}')
    raise SystemExit(1)
ledger = Path('.phase_control/run_ledger.jsonl')
lines = [line for line in ledger.read_text().splitlines() if line.strip()]
if not lines:
    print('FAIL: run_ledger.jsonl is empty')
    raise SystemExit(1)
events = []
for i, line in enumerate(lines, 1):
    obj = json.loads(line)
    events.append(obj.get('event'))
    if not isinstance(obj.get('data', {}), dict):
        print(f'FAIL: line {i} data is not a JSON object')
        raise SystemExit(1)
if not any(evt in ('gate_result', 'verdict_checked') for evt in events):
    print('FAIL: missing gate_result or verdict_checked event')
    raise SystemExit(1)
print('OK')
PY
    then
        pass "C7: orchestrator.check_verdict() 写入有效 run ledger"
    else
        fail "C7: orchestrator.check_verdict() 未正确写入 run ledger"
    fi

    local status_output
    if status_output=$(bash scripts/hmte-status.sh 2>&1); then
        if printf '%s' "$status_output" | grep -q "Run Ledger" && printf '%s' "$status_output" | grep -q "gate_result" && bash scripts/hmte-doctor.sh >/dev/null 2>&1; then
            pass "C7: hmte-status.sh / hmte-doctor.sh 读取合法 run ledger"
        else
            fail "C7: hmte-status.sh / hmte-doctor.sh 未正确处理合法 run ledger"
        fi
    else
        fail "C7: hmte-status.sh 未能读取合法 run ledger"
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
test_run_ledger_closure

# 清理
cleanup

echo ""
echo "=========================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "=========================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
