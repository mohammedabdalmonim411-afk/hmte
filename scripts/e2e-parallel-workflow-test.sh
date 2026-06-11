#!/usr/bin/env bash
# e2e-parallel-workflow-test.sh — v1.7-rework E2E tests (31 tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"
export HMTE_RECEIPT_MODE=compat

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASSED=0; FAILED=0; TOTAL=0
pass() { TOTAL=$((TOTAL+1)); PASSED=$((PASSED+1)); echo -e "${GREEN}✅ PASS: $1${NC}"; }
fail() { TOTAL=$((TOTAL+1)); FAILED=$((FAILED+1)); echo -e "${RED}❌ FAIL: $1${NC}"; echo "  Detail: $2"; }
info() { echo -e "${YELLOW}ℹ $*${NC}"; }

setup_test_env() {
    rm -rf .phase_control
    mkdir -p .phase_control/{evidence,verdicts,logs,instructions,state,errors,delegations,pids,traces,amendments}
    echo '{"session_id":"test","mode":"test","workflow":"test","task":"test","status":"IDLE","created_at":"2026-06-02T00:00:00Z"}' > .phase_control/session.json
    echo '{"goal":"test","status":"IDLE","updated_at":"2026-06-02T00:00:00Z"}' > .phase_control/state.json
    : > .phase_control/run_ledger.jsonl
}

_ts() { echo "2099-01-01T00:00:00Z"; }

make_receipt() {
    local phase_id="$1" attempt="$2" role="$3" worker_id="${4:-}"
    local receipt_file
    local instruction_file
    local expected_output
    if [ -n "$worker_id" ]; then
        receipt_file=".phase_control/delegations/${phase_id}_${worker_id}_attempt_${attempt}_${role}.json"
        instruction_file=".phase_control/instructions/${phase_id}_${worker_id}_attempt_${attempt}_${role}.json"
    else
        receipt_file=".phase_control/delegations/${phase_id}_attempt_${attempt}_${role}.json"
        instruction_file=".phase_control/instructions/${phase_id}_attempt_${attempt}_${role}.json"
    fi

    if [ "$role" = "worker" ]; then
        if [ -n "$worker_id" ]; then
            expected_output=".phase_control/evidence/${phase_id}_${worker_id}_attempt_${attempt}.json"
        else
            expected_output=".phase_control/evidence/${phase_id}_attempt_${attempt}.json"
        fi
    else
        expected_output=".phase_control/verdicts/${phase_id}_attempt_${attempt}.json"
    fi

    python3 - "$phase_id" "$attempt" "$role" "$worker_id" "$receipt_file" "$(_ts)" "$instruction_file" "$expected_output" <<PYEOF
import json, sys
phase_id, attempt, role, worker_id = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
receipt_file, ts, instruction_file, expected_output = sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8]
instr = {"phase_id": phase_id, "attempt": attempt, "role": role, "created_at": ts, "status": "PENDING"}
if worker_id:
    instr["worker_id"] = worker_id
with open(instruction_file, "w") as f:
    json.dump(instr, f, indent=2)
r = {
    "phase_id": phase_id,
    "attempt": attempt,
    "role": role,
    "created_at": ts,
    "delegated_at": ts,
    "timestamp": ts,
    "leader_session_id": "test",
    "instruction_path": instruction_file,
    "leader_instruction_path": instruction_file,
    "expected_output_path": expected_output,
    "trust_level": "INTENT_ONLY",
    "delegation_trust_level": "INTENT_ONLY",
    "delegation_method": "delegate_task",
    "delegate_task_params": {}
}
if worker_id:
    r["worker_id"] = worker_id
with open(receipt_file, "w") as f:
    json.dump(r, f, indent=2)
PYEOF
}

write_shard_evidence() {
    local phase_id="$1" wid="$2" attempt="$3" status="${4:-PASS}"
    local changed="${5:-src/$wid.py}"
    cat > ".phase_control/evidence/${phase_id}_${wid}_attempt_${attempt}.json" <<EOE
{"phase_id":"${phase_id}","attempt":${attempt},"worker_name":"${wid}","worker_id":"${wid}","goal_summary":"Task ${wid}","planned_output":"done","changed_files":["${changed}"],"commands_run":["echo ${wid}"],"command_exit_codes":[0],"generated_at":"$(_ts)","timestamp":"$(_ts)","status":"${status}","unresolved_risks":[],"command_log_path":".phase_control/logs/${phase_id}_${wid}_attempt_${attempt}.commands.jsonl"}
EOE
    cat > ".phase_control/logs/${phase_id}_${wid}_attempt_${attempt}.commands.jsonl" <<EOL
{"phase_id":"${phase_id}","attempt":${attempt},"worker_id":"${wid}","command":"printf ${wid} >> ${changed}","exit_code":0,"runner":"hmte exec","started_at":"$(_ts)","ended_at":"$(_ts)","output_tail":"${changed}"}
EOL
}

write_verdict() {
    local phase_id="$1" attempt="$2" status="${3:-PASS}"
    cat > ".phase_control/verdicts/${phase_id}_attempt_${attempt}.json"
}

run_gate_pass() { set +e; O=$(bash src/skills/hmte/scripts/phase_gate.sh "$1" --attempt "${2:-1}" 2>&1); E=$?; set -e; [ $E -eq 0 ] && return 0 || { echo "$O"; return 1; }; }
run_gate_fail() { set +e; O=$(bash src/skills/hmte/scripts/phase_gate.sh "$1" --attempt "${2:-1}" 2>&1); E=$?; set -e; [ $E -ne 0 ] && return 0 || { echo "Expected FAIL: $O"; return 1; }; }
run_gate_fail_check() {
    local phase_id="$1" expected_check="$2" attempt="${3:-1}"
    set +e
    O=$(bash src/skills/hmte/scripts/phase_gate.sh "$phase_id" --attempt "$attempt" 2>&1)
    E=$?
    set -e
    if [ $E -ne 0 ] && echo "$O" | grep -q "$expected_check"; then
        return 0
    else
        echo "Expected FAIL with '$expected_check', got exit=$E: $O"
        return 1
    fi
}

run_final_check_pass() {
    set +e
    O=$(bash scripts/hmte-final-check.sh --mode dev 2>&1)
    E=$?
    set -e
    [ $E -eq 0 ] && return 0 || { echo "$O"; return 1; }
}

run_final_check_fail() {
    set +e
    O=$(bash scripts/hmte-final-check.sh --mode dev 2>&1)
    E=$?
    set -e
    [ $E -ne 0 ] && return 0 || { echo "Expected final-check FAIL: $O"; return 1; }
}

write_parallel_final_fixture() {
    local phase_id="$1"
    setup_test_env
    cat > .phase_control/phases.json <<EOP
{"phases":[{"phase_id":"${phase_id}","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}
EOP
    make_receipt "$phase_id" 1 "worker" "w1"
    make_receipt "$phase_id" 1 "worker" "w2"
    make_receipt "$phase_id" 1 "verifier"
    write_shard_evidence "$phase_id" "w1" 1 "PASS" "README.md"
    write_shard_evidence "$phase_id" "w2" 1 "PASS" "CHANGELOG.md"
    write_verdict "$phase_id" 1 "PASS" <<EOV
{"status":"PASS","phase_id":"${phase_id}","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"test disposition"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md","CHANGELOG.md"],"evidence_paths":[".phase_control/evidence/${phase_id}_w1_attempt_1.json",".phase_control/evidence/${phase_id}_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"verified by reading README.md and CHANGELOG.md"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/${phase_id}_w1_attempt_1.json",".phase_control/evidence/${phase_id}_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/${phase_id}_w1_attempt_1.commands.jsonl",".phase_control/logs/${phase_id}_w2_attempt_1.commands.jsonl"]}
EOV
}

write_sequential_final_fixture() {
    local phase_id="$1"
    setup_test_env
    cat > .phase_control/phases.json <<EOP
{"phases":[{"phase_id":"${phase_id}","objective":"T","acceptance_criteria":["done"]}]}
EOP
    make_receipt "$phase_id" 1 "worker"
    make_receipt "$phase_id" 1 "verifier"
    cat > ".phase_control/evidence/${phase_id}_attempt_1.json" <<EOE
{"phase_id":"${phase_id}","attempt":1,"worker_name":"w","goal_summary":"T","planned_output":"done","changed_files":["README.md"],"commands_run":["printf ok >> README.md"],"command_exit_codes":[0],"generated_at":"$(_ts)","timestamp":"$(_ts)","status":"PASS","unresolved_risks":[],"command_log_path":".phase_control/logs/${phase_id}_attempt_1.commands.jsonl"}
EOE
    cat > ".phase_control/logs/${phase_id}_attempt_1.commands.jsonl" <<EOL
{"phase_id":"${phase_id}","attempt":1,"command":"printf ok >> README.md","exit_code":0,"runner":"hmte exec","started_at":"$(_ts)","ended_at":"$(_ts)","output_tail":"README.md"}
EOL
    write_verdict "$phase_id" 1 "PASS" <<EOV
{"status":"PASS","phase_id":"${phase_id}","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"test disposition"}],"re_verification_conclusion":"Verified sequential phase evidence and command log","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/${phase_id}_attempt_1.json",".phase_control/logs/${phase_id}_attempt_1.commands.jsonl"],"criteria_passed":[{"criterion":"done","evidence":"verified by reading README.md"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true}}
EOV
}


# ===== TEST 1: sequential phase old logic PASS =====
t01() {
    info "T1: sequential phase 旧逻辑仍 PASS"
    setup_test_env
    echo '{"phases":[{"id":"seq1","objective":"Test","acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "seq1" 1 "worker"
    make_receipt "seq1" 1 "verifier"
    cat > .phase_control/evidence/seq1_attempt_1.json <<EOE
{"phase_id":"seq1","attempt":1,"worker_name":"w","goal_summary":"T","planned_output":"done","changed_files":["README.md"],"commands_run":["echo ok"],"command_exit_codes":[0],"generated_at":"$(_ts)","timestamp":"$(_ts)","status":"PASS","unresolved_risks":[],"command_log_path":".phase_control/logs/seq1_attempt_1.commands.jsonl"}
EOE
    cat > .phase_control/logs/seq1_attempt_1.commands.jsonl <<'EOL'
{"phase_id":"seq1","attempt":1,"command":"echo ok","exit_code":0,"runner":"hmte exec","started_at":"2099-01-01T00:00:00Z","ended_at":"2099-01-01T00:00:01Z","output_tail":"ok"}
EOL
    write_verdict "seq1" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"seq1","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all changes are correct and complete","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/seq1_attempt_1.json",".phase_control/logs/seq1_attempt_1.commands.jsonl"],"criteria_passed":[{"criterion":"done","evidence":"verified by reading file contents"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true}}
EOV
    run_gate_pass "seq1" 1 && pass "T1" || fail "T1" "should pass"
}

# ===== TEST 2: parallel phase two workers PASS (shard-only, no fake single files) =====
t02() {
    info "T2: parallel PASS — shard-only evidence/receipt"
    setup_test_env
    cat > .phase_control/phases.json <<'EOP'
{"phases":[{"id":"par1","objective":"Test","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"impl-core","scope":"Core","forbidden_paths":["src/api/"]},{"worker_id":"impl-api","scope":"API","forbidden_paths":["src/core/"]}],"acceptance_criteria":["Both done"]}]}
EOP
    make_receipt "par1" 1 "worker" "impl-core"
    make_receipt "par1" 1 "worker" "impl-api"
    make_receipt "par1" 1 "verifier"
    write_shard_evidence "par1" "impl-core" 1 "PASS" "src/core/main.py"
    write_shard_evidence "par1" "impl-api" 1 "PASS" "src/api/main.py"
    write_verdict "par1" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par1","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md","CHANGELOG.md"],"evidence_paths":[".phase_control/evidence/par1_impl-core_attempt_1.json",".phase_control/evidence/par1_impl-api_attempt_1.json"],"criteria_passed":[{"criterion":"Both done","evidence":"verified by reading file contents"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"impl-core","evidence_status":"PASS","changed_files_count":1},{"worker_id":"impl-api","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par1_impl-core_attempt_1.json",".phase_control/evidence/par1_impl-api_attempt_1.json"],"command_log_paths":[".phase_control/logs/par1_impl-core_attempt_1.commands.jsonl",".phase_control/logs/par1_impl-api_attempt_1.commands.jsonl"]}
EOV
    run_gate_pass "par1" 1 && pass "T2" || fail "T2" "should pass"
}

# ===== TEST 3: missing one worker evidence FAIL =====
t03() {
    info "T3: 缺少一个 Worker evidence FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par2","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par2" 1 "worker" "w1"
    make_receipt "par2" 1 "worker" "w2"
    make_receipt "par2" 1 "verifier"
    write_shard_evidence "par2" "w1" 1
    write_shard_evidence "par2" "w2" 1
    write_verdict "par2" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par2","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/w1.py","src/w2.py"],"evidence_paths":[".phase_control/evidence/par2_w1_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"verified by reading file contents"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par2_w1_attempt_1.json"],"command_log_paths":[".phase_control/logs/par2_w1_attempt_1.commands.jsonl",".phase_control/logs/par2_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par2" "CHECK4" 1 && pass "T3" || fail "T3" "should fail with CHECK4"
}

# ===== TEST 4: verdict missing evidence ref FAIL =====
t04() {
    info "T4: verdict 未引用全部 evidence FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par3","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par3" 1 "worker" "w1"
    make_receipt "par3" 1 "worker" "w2"
    make_receipt "par3" 1 "verifier"
    write_shard_evidence "par3" "w1" 1; write_shard_evidence "par3" "w2" 1
    write_verdict "par3" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par3","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/par3_w1_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par3_w1_attempt_1.json"],"command_log_paths":[".phase_control/logs/par3_w1_attempt_1.commands.jsonl",".phase_control/logs/par3_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par3" "CHECK4" 1 && pass "T4" || fail "T4" "should fail with CHECK4"
}

# ===== TEST 5: join_verification missing FAIL =====
t05() {
    info "T5: join_verification 缺失 FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par4","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par4" 1 "worker" "w1"
    make_receipt "par4" 1 "worker" "w2"
    make_receipt "par4" 1 "verifier"
    write_shard_evidence "par4" "w1" 1; write_shard_evidence "par4" "w2" 1
    write_verdict "par4" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par4","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/w1.py","src/w2.py"],"evidence_paths":[".phase_control/evidence/par4_w1_attempt_1.json",".phase_control/evidence/par4_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"evidence_paths":[".phase_control/evidence/par4_w1_attempt_1.json",".phase_control/evidence/par4_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par4_w1_attempt_1.commands.jsonl",".phase_control/logs/par4_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par4" "CHECK6" 1 && pass "T5" || fail "T5" "should fail with CHECK6"
}

# ===== TEST 6: changed_files overlap FAIL =====
t06() {
    info "T6: worker changed_files 重叠 FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par5","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par5" 1 "worker" "w1"
    make_receipt "par5" 1 "worker" "w2"
    make_receipt "par5" 1 "verifier"
    write_shard_evidence "par5" "w1" 1 "PASS" "src/shared.py"
    write_shard_evidence "par5" "w2" 1 "PASS" "src/shared.py"
    write_verdict "par5" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par5","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/shared.py"],"evidence_paths":[".phase_control/evidence/par5_w1_attempt_1.json",".phase_control/evidence/par5_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par5_w1_attempt_1.json",".phase_control/evidence/par5_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par5_w1_attempt_1.commands.jsonl",".phase_control/logs/par5_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par5" "CHECK11" 1 && pass "T6" || fail "T6" "should fail with CHECK11"
}

# ===== TEST 7: missing_shards nonempty FAIL =====
t07() {
    info "T7: missing_shards 非空 FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par6","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par6" 1 "worker" "w1"
    make_receipt "par6" 1 "worker" "w2"
    make_receipt "par6" 1 "verifier"
    write_shard_evidence "par6" "w1" 1; write_shard_evidence "par6" "w2" 1
    write_verdict "par6" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par6","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/w1.py","src/w2.py"],"evidence_paths":[".phase_control/evidence/par6_w1_attempt_1.json",".phase_control/evidence/par6_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":["w3"],"per_shard_results":[]},"evidence_paths":[".phase_control/evidence/par6_w1_attempt_1.json",".phase_control/evidence/par6_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par6_w1_attempt_1.commands.jsonl",".phase_control/logs/par6_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par6" "CHECK9" 1 && pass "T7" || fail "T7" "should fail with CHECK9"
}

# ===== TEST 8: Run Ledger parallel events PASS =====
t08() {
    info "T8: Run Ledger 记录 parallel/shard/join 事件 PASS"
    setup_test_env
    cat > .phase_control/run_ledger.jsonl <<'EOL'
{"timestamp":"2099-01-01T00:00:00Z","event":"parallel_phase_started","data":{"phase_id":"par1","worker_count":2}}
{"timestamp":"2099-01-01T00:00:01Z","event":"worker_shard_delegated","data":{"phase_id":"par1","worker_id":"w1","attempt":1}}
{"timestamp":"2099-01-01T00:00:02Z","event":"worker_shard_delegated","data":{"phase_id":"par1","worker_id":"w2","attempt":1}}
{"timestamp":"2099-01-01T00:00:03Z","event":"worker_shard_evidence_ready","data":{"phase_id":"par1","worker_id":"w1","attempt":1}}
{"timestamp":"2099-01-01T00:00:04Z","event":"worker_shard_evidence_ready","data":{"phase_id":"par1","worker_id":"w2","attempt":1}}
{"timestamp":"2099-01-01T00:00:05Z","event":"join_verification_result","data":{"phase_id":"par1","verdict":"PASS"}}
{"timestamp":"2099-01-01T00:00:06Z","event":"parallel_phase_gate_result","data":{"phase_id":"par1","verdict":"PASS"}}
EOL
    C=$(wc -l < .phase_control/run_ledger.jsonl | tr -d ' ')
    [ "$C" -eq 7 ] && grep -q parallel_phase_started .phase_control/run_ledger.jsonl && grep -q worker_shard_delegated .phase_control/run_ledger.jsonl && grep -q join_verification_result .phase_control/run_ledger.jsonl && pass "T8" || fail "T8" "ledger events missing"
}

# ===== TEST 9: hmte-status.sh shows parallel PASS =====
t09() {
    info "T9: hmte-status.sh 能展示 parallel 事件 PASS"
    [ -f .phase_control/run_ledger.jsonl ] || t08
    set +e; bash scripts/hmte-status.sh 2>&1 >/dev/null; E=$?; set -e
    [ $E -eq 0 ] || [ $E -eq 1 ] && pass "T9" || fail "T9" "status crashed"
}

# ===== TEST 10: hmte-doctor.sh parallel health PASS =====
t10() {
    info "T10: hmte-doctor.sh parallel health PASS"
    set +e; bash scripts/hmte-doctor.sh 2>&1 >/dev/null; E=$?; set -e
    [ $E -eq 0 ] || [ $E -eq 1 ] && pass "T10" || fail "T10" "doctor crashed"
}

# ===== TEST 11: forbidden_paths own violation FAIL (P0-B) =====
t11() {
    info "T11: Worker 改自己的 forbidden_paths → FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par7","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":["src/core/"]},{"worker_id":"w2","scope":"T","forbidden_paths":["src/api/"]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par7" 1 "worker" "w1"
    make_receipt "par7" 1 "worker" "w2"
    make_receipt "par7" 1 "verifier"
    write_shard_evidence "par7" "w1" 1 "PASS" "src/core/secret.py"
    write_shard_evidence "par7" "w2" 1 "PASS" "src/api/handler.py"
    write_verdict "par7" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par7","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/core/secret.py","src/api/handler.py"],"evidence_paths":[".phase_control/evidence/par7_w1_attempt_1.json",".phase_control/evidence/par7_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par7_w1_attempt_1.json",".phase_control/evidence/par7_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par7_w1_attempt_1.commands.jsonl",".phase_control/logs/par7_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par7" "CHECK10" 1 && pass "T11" || fail "T11" "should fail with CHECK10"
}

# ===== TEST 12: verdict missing one expected evidence ref FAIL =====
t12() {
    info "T12: verdict 少引用一个 expected evidence FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par8","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par8" 1 "worker" "w1"
    make_receipt "par8" 1 "worker" "w2"
    make_receipt "par8" 1 "verifier"
    write_shard_evidence "par8" "w1" 1; write_shard_evidence "par8" "w2" 1
    write_verdict "par8" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par8","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/par8_w1_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par8_w1_attempt_1.json"],"command_log_paths":[".phase_control/logs/par8_w1_attempt_1.commands.jsonl",".phase_control/logs/par8_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par8" "CHECK4" 1 && pass "T12" || fail "T12" "should fail with CHECK4"
}

# ===== TEST 13: command log not at --worker-id path FAIL =====
t13() {
    info "T13: command log 未按 --worker-id 路径生成 FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par9","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par9" 1 "worker" "w1"
    make_receipt "par9" 1 "worker" "w2"
    make_receipt "par9" 1 "verifier"
    write_shard_evidence "par9" "w1" 1; write_shard_evidence "par9" "w2" 1
    # Wrong command log path (no worker_id)
    rm -f .phase_control/logs/par9_w1_attempt_1.commands.jsonl .phase_control/logs/par9_w2_attempt_1.commands.jsonl
    cat > .phase_control/logs/par9_attempt_1.commands.jsonl <<'EOL'
{"phase_id":"par9","attempt":1,"command":"echo combined","exit_code":0,"runner":"hmte exec","started_at":"2099-01-01T00:00:00Z","ended_at":"2099-01-01T00:00:01Z","output_tail":"combined"}
EOL
    write_verdict "par9" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par9","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/w1.py","src/w2.py"],"evidence_paths":[".phase_control/evidence/par9_w1_attempt_1.json",".phase_control/evidence/par9_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par9_w1_attempt_1.json",".phase_control/evidence/par9_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par9_w1_attempt_1.commands.jsonl",".phase_control/logs/par9_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par9" "command_log" 1 && pass "T13" || fail "T13" "should fail with command_log"
}

# ===== TEST 14: worker_id path injection FAIL =====
t14() {
    info "T14: worker_id 路径注入 FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par10","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"../evil","scope":"Evil","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    write_verdict "par10" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par10","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":[],"evidence_paths":[],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[]},"evidence_paths":[],"command_log_paths":[]}
EOV
    run_gate_fail "par10" 1 && pass "T14" || fail "T14" "should fail"
}

# ===== TEST 15: BLOCKED evidence but PASS verdict FAIL =====
t15() {
    info "T15: evidence.status=BLOCKED 但 verdict PASS → FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par11","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par11" 1 "worker" "w1"
    make_receipt "par11" 1 "worker" "w2"
    make_receipt "par11" 1 "verifier"
    write_shard_evidence "par11" "w1" 1 "PASS" "src/w1.py"
    write_shard_evidence "par11" "w2" 1 "BLOCKED" "src/w2.py"
    write_verdict "par11" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par11","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/par11_w1_attempt_1.json",".phase_control/evidence/par11_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"BLOCKED","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par11_w1_attempt_1.json",".phase_control/evidence/par11_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par11_w1_attempt_1.commands.jsonl",".phase_control/logs/par11_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par11" "CHECK12" 1 && pass "T15" || fail "T15" "should fail with CHECK12"
}

# ===== TEST 16: phase_id key compatibility (P0-A) =====
t16() {
    info "T16: phases.json 用 phase_id 而非 id → parallel gate 仍生效"
    setup_test_env
    echo '{"phases":[{"phase_id":"par_pha","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par_pha" 1 "worker" "w1"
    make_receipt "par_pha" 1 "worker" "w2"
    make_receipt "par_pha" 1 "verifier"
    write_shard_evidence "par_pha" "w1" 1; write_shard_evidence "par_pha" "w2" 1
    # Missing shard w2 evidence → should FAIL (not be treated as sequential)
    rm -f .phase_control/evidence/par_pha_w2_attempt_1.json
    write_verdict "par_pha" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par_pha","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/par_pha_w1_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par_pha_w1_attempt_1.json"],"command_log_paths":[".phase_control/logs/par_pha_w1_attempt_1.commands.jsonl",".phase_control/logs/par_pha_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par_pha" "evidence" 1 && pass "T16" || fail "T16" "should fail with evidence (phase_id key)"
}

# ===== TEST 17: forbidden glob src/core/** protects src/core/secret.py (P0-B) =====
t17() {
    info "T17: forbidden glob 模式匹配 FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par_glob","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":["src/core/**"]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par_glob" 1 "worker" "w1"
    make_receipt "par_glob" 1 "worker" "w2"
    make_receipt "par_glob" 1 "verifier"
    write_shard_evidence "par_glob" "w1" 1 "PASS" "src/core/secret.py"
    write_shard_evidence "par_glob" "w2" 1 "PASS" "src/w2.py"
    write_verdict "par_glob" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par_glob","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/core/secret.py","src/w2.py"],"evidence_paths":[".phase_control/evidence/par_glob_w1_attempt_1.json",".phase_control/evidence/par_glob_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par_glob_w1_attempt_1.json",".phase_control/evidence/par_glob_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par_glob_w1_attempt_1.commands.jsonl",".phase_control/logs/par_glob_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par_glob" "CHECK10" 1 && pass "T17" || fail "T17" "should fail with CHECK10 (glob match)"
}

# ===== TEST 18: forbidden src/api/ does NOT match src/api_v2/foo.py (P0-B) =====
t18() {
    info "T18: forbidden src/api/ 不误杀 src/api_v2/ → PASS"
    setup_test_env
    echo '{"phases":[{"id":"par_noglob","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":["src/api/"]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
        make_receipt "par_noglob" 1 "worker" "w1"
    make_receipt "par_noglob" 1 "worker" "w2"
    make_receipt "par_noglob" 1 "verifier"
    write_shard_evidence "par_noglob" "w1" 1 "PASS" "src/api_v2/foo.py"
    write_shard_evidence "par_noglob" "w2" 1 "PASS" "src/w2.py"
    write_verdict "par_noglob" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par_noglob","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["README.md","CHANGELOG.md"],"evidence_paths":[".phase_control/evidence/par_noglob_w1_attempt_1.json",".phase_control/evidence/par_noglob_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par_noglob_w1_attempt_1.json",".phase_control/evidence/par_noglob_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par_noglob_w1_attempt_1.commands.jsonl",".phase_control/logs/par_noglob_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_pass "par_noglob" 1 && pass "T18" || fail "T18" "should pass (no false positive)"
}

# ===== TEST 19: evidence missing worker_id → FAIL (P0-C) =====
t19() {
    info "T19: evidence 缺 worker_id → FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par_nwid","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w2","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par_nwid" 1 "worker" "w1"
    make_receipt "par_nwid" 1 "worker" "w2"
    make_receipt "par_nwid" 1 "verifier"
    # w1 evidence missing worker_id
    cat > .phase_control/evidence/par_nwid_w1_attempt_1.json <<'EOE'
{"phase_id":"par_nwid","attempt":1,"worker_name":"w1","goal_summary":"T","planned_output":"done","changed_files":["src/w1.py"],"commands_run":["echo 1"],"command_exit_codes":[0],"generated_at":"2099-01-01T00:00:00Z","status":"PASS"}
EOE
    write_shard_evidence "par_nwid" "w2" 1
    write_verdict "par_nwid" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par_nwid","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified all shard changes are correct and complete","independently_verified_files":["src/w1.py","src/w2.py"],"evidence_paths":[".phase_control/evidence/par_nwid_w1_attempt_1.json",".phase_control/evidence/par_nwid_w2_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1},{"worker_id":"w2","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par_nwid_w1_attempt_1.json",".phase_control/evidence/par_nwid_w2_attempt_1.json"],"command_log_paths":[".phase_control/logs/par_nwid_w1_attempt_1.commands.jsonl",".phase_control/logs/par_nwid_w2_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par_nwid" "worker_id" 1 && pass "T19" || fail "T19" "should fail with worker_id check"
}

# ===== TEST 20: verdict JSON corrupted → phase_gate FAIL with diagnostics (P0-D) =====
t20() {
    info "T20: verdict JSON 损坏 → phase_gate FAIL with diagnostics"
    setup_test_env
    echo '{"phases":[{"id":"par_bad","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par_bad" 1 "worker" "w1"
    make_receipt "par_bad" 1 "verifier"
    write_shard_evidence "par_bad" "w1" 1
    echo 'NOT VALID JSON{' > .phase_control/verdicts/par_bad_attempt_1.json
    set +e
    O=$(bash src/skills/hmte/scripts/phase_gate.sh "par_bad" --attempt 1 2>&1)
    E=$?
    set -e
    if [ $E -ne 0 ] && echo "$O" | grep -Eq 'Flow audit failed|JSON 解析失败|verdict invalid JSON'; then
        pass "T20"
    else
        fail "T20" "should fail on corrupted verdict with diagnostics, got exit=$E: $O"
    fi
}

# ===== TEST 21: final-check accepts parallel shard-only chain =====
t21() {
    info "T21: parallel shard-only chain → hmte-final-check dev PASS"
    write_parallel_final_fixture "par_final"
    run_final_check_pass && pass "T21" || fail "T21" "final-check should pass for shard-only parallel phase"
}

# ===== TEST 22: final-check catches missing shard worker receipt =====
t22() {
    info "T22: parallel 缺 shard worker receipt → final-check FAIL"
    write_parallel_final_fixture "par_missing_receipt"
    rm -f .phase_control/delegations/par_missing_receipt_w2_attempt_1_worker.json
    run_final_check_fail && pass "T22" || fail "T22" "final-check should fail when shard worker receipt is missing"
}

# ===== TEST 23: final-check catches missing shard evidence =====
t23() {
    info "T23: parallel 缺 shard evidence → final-check FAIL"
    write_parallel_final_fixture "par_missing_evidence"
    rm -f .phase_control/evidence/par_missing_evidence_w2_attempt_1.json
    run_final_check_fail && pass "T23" || fail "T23" "final-check should fail when shard evidence is missing"
}

# ===== TEST 24: sequential final-check legacy path remains PASS =====
t24() {
    info "T24: sequential final-check 旧链路仍 PASS"
    write_sequential_final_fixture "seq_final"
    run_final_check_pass && pass "T24" || fail "T24" "sequential final-check should still pass"
}

# ===== TEST 25: parallel command log runner=terminal FAIL =====
t25() {
    info "T25: parallel command log runner=terminal → FAIL"
    write_parallel_final_fixture "par_bad_runner"
    cat > .phase_control/logs/par_bad_runner_w1_attempt_1.commands.jsonl <<'EOL'
{"phase_id":"par_bad_runner","attempt":1,"worker_id":"w1","command":"printf bad >> README.md","exit_code":0,"runner":"terminal","started_at":"2099-01-01T00:00:00Z","ended_at":"2099-01-01T00:00:01Z","output_tail":"README.md"}
EOL
    run_gate_fail_check "par_bad_runner" "runner=terminal" 1 && pass "T25" || fail "T25" "should fail with runner=terminal"
}

# ===== TEST 26: parallel command log non-JSON FAIL =====
t26() {
    info "T26: parallel command log 非 JSON → FAIL"
    write_parallel_final_fixture "par_bad_jsonlog"
    echo 'not json' > .phase_control/logs/par_bad_jsonlog_w1_attempt_1.commands.jsonl
    run_gate_fail_check "par_bad_jsonlog" "JSON 解析失败" 1 && pass "T26" || fail "T26" "should fail with JSON parse diagnostic"
}

# ===== TEST 27: parallel command log worker_id mismatch FAIL =====
t27() {
    info "T27: parallel command log worker_id 不匹配 → FAIL"
    write_parallel_final_fixture "par_bad_workerid"
    cat > .phase_control/logs/par_bad_workerid_w1_attempt_1.commands.jsonl <<'EOL'
{"phase_id":"par_bad_workerid","attempt":1,"worker_id":"w2","command":"printf bad >> README.md","exit_code":0,"runner":"hmte exec","started_at":"2099-01-01T00:00:00Z","ended_at":"2099-01-01T00:00:01Z","output_tail":"README.md"}
EOL
    run_gate_fail_check "par_bad_workerid" "worker_id 不匹配" 1 && pass "T27" || fail "T27" "should fail with worker_id mismatch"
}

# ===== TEST 28: parallel command log phase_id mismatch FAIL =====
t28() {
    info "T28: parallel command log phase_id 不匹配 → FAIL"
    write_parallel_final_fixture "par_bad_phaseid"
    cat > .phase_control/logs/par_bad_phaseid_w1_attempt_1.commands.jsonl <<'EOL'
{"phase_id":"other_phase","attempt":1,"worker_id":"w1","command":"printf bad >> README.md","exit_code":0,"runner":"hmte exec","started_at":"2099-01-01T00:00:00Z","ended_at":"2099-01-01T00:00:01Z","output_tail":"README.md"}
EOL
    run_gate_fail_check "par_bad_phaseid" "phase_id 不匹配" 1 && pass "T28" || fail "T28" "should fail with phase_id mismatch"
}

# ===== TEST 29: parallel command log full content validation normal PASS =====
t29() {
    info "T29: parallel command log 完整内容校验正常 PASS"
    write_parallel_final_fixture "par_log_ok"
    run_gate_pass "par_log_ok" 1 && pass "T29" || fail "T29" "valid parallel command logs should pass"
}

# ===== TEST 30: installed skill missing parallel_gate_check.py MUST BLOCK =====
t30() {
    info "T30: 安装态缺少 parallel_gate_check.py → parallel_safe 必须 BLOCK"
    write_parallel_final_fixture "par_install"

    local tmp_home skill_dir tmp_install_log
    tmp_home="$(mktemp -d)"
    tmp_install_log="$(mktemp)"

    set +e
    HERMES_HOME="$tmp_home" bash install-to-hermes.sh --profile test --force >"$tmp_install_log" 2>&1
    local install_exit=$?
    set -e

    if [ "$install_exit" -ne 0 ]; then
        cat "$tmp_install_log"
        rm -rf "$tmp_home"
        rm -f "$tmp_install_log"
        fail "T30" "install-to-hermes.sh should succeed in temp Hermes home"
        return
    fi

    skill_dir="$tmp_home/profiles/test/skills/hmte"
    if [ ! -f "$skill_dir/scripts/parallel_gate_check.py" ]; then
        cat "$tmp_install_log"
        rm -rf "$tmp_home"
        rm -f "$tmp_install_log"
        fail "T30" "parallel_gate_check.py should be installed"
        return
    fi

    rm -f "$skill_dir/scripts/parallel_gate_check.py"
    set +e
    O=$(bash "$skill_dir/scripts/phase_gate.sh" "par_install" --attempt 1 2>&1)
    E=$?
    set -e

    rm -rf "$tmp_home"
    rm -f "$tmp_install_log"

if [ $E -ne 0 ] && echo "$O" | grep -q "requires parallel_gate_check.py"; then
        pass "T30"
    else
        fail "T30" "expected fail-closed when installed skill is missing parallel_gate_check.py, got exit=$E: $O"
    fi
}

# ===== TEST 31: duplicate worker_id MUST FAIL =====
t31() {
    info "T31: duplicate worker_id → phase_gate FAIL"
    setup_test_env
    echo '{"phases":[{"id":"par_dup","objective":"T","execution_mode":"parallel_safe","parallel_workers":[{"worker_id":"w1","scope":"T","forbidden_paths":[]},{"worker_id":"w1","scope":"T","forbidden_paths":[]}],"acceptance_criteria":["done"]}]}' > .phase_control/phases.json
    make_receipt "par_dup" 1 "worker" "w1"
    make_receipt "par_dup" 1 "verifier"
    write_shard_evidence "par_dup" "w1" 1 "PASS" "README.md"
    write_verdict "par_dup" 1 "PASS" <<'EOV'
{"status":"PASS","phase_id":"par_dup","attempt":1,"timestamp":"2099-01-01T00:01:00Z","adversarial_scorecard":{"verification_method":"manual_review","risk_disposition":[{"risk":"t","disposition":"accepted","reason":"t"}],"re_verification_conclusion":"Verified duplicate worker_id should be rejected","independently_verified_files":["README.md"],"evidence_paths":[".phase_control/evidence/par_dup_w1_attempt_1.json"],"criteria_passed":[{"criterion":"done","evidence":"v"}],"criteria_failed":[],"residual_risks":["none"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true},"join_verification":{"all_worker_evidence_checked":true,"all_command_logs_checked":true,"missing_shards":[],"per_shard_results":[{"worker_id":"w1","evidence_status":"PASS","changed_files_count":1}]},"evidence_paths":[".phase_control/evidence/par_dup_w1_attempt_1.json"],"command_log_paths":[".phase_control/logs/par_dup_w1_attempt_1.commands.jsonl"]}
EOV
    run_gate_fail_check "par_dup" "duplicate worker_id" 1 && pass "T31" || fail "T31" "should fail with duplicate worker_id"
}

# ===== Main =====
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "TAF Parallel Workflow E2E Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

t01; t02; t03; t04; t05; t06; t07; t08; t09; t10
t11; t12; t13; t14; t15; t16; t17; t18; t19; t20
t21; t22; t23; t24; t25; t26; t27; t28; t29; t30; t31

rm -rf .phase_control

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASSED passed, $FAILED failed (total: $TOTAL)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$FAILED" -gt 0 ] && exit 1 || exit 0
