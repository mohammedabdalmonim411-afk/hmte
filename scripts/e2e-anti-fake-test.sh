#!/bin/bash
# e2e-anti-fake-test.sh
# 端到端反伪装测试

set -euo pipefail

SKILL_DIR="src/skills/hmte"
# Ensure E2E tests run independently of local Hermes installation
export HMTE_SKILL_DIR="$PWD/$SKILL_DIR"
AUDIT="python3 $SKILL_DIR/scripts/hmte-audit-flow.py"
GATE="bash $SKILL_DIR/scripts/phase_gate.sh"
PHASE="test_anti_fake"
ATTEMPT=1
PASS_COUNT=0
FAIL_COUNT=0

setup() {
    rm -rf .phase_control/delegations .phase_control/evidence .phase_control/verdicts .phase_control/logs
    mkdir -p .phase_control/{delegations,evidence,verdicts,logs}
    touch .phase_control/evidence/.gitkeep .phase_control/verdicts/.gitkeep .phase_control/logs/.gitkeep
}

log_pass() {
    echo "  ✅ $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
    echo "  ❌ $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ---- Helper: validate JSON file ----
validate_json_file() {
    if ! python3 -m json.tool "$1" >/dev/null 2>&1; then
        echo "  ❌ Invalid JSON: $1"
        return 1
    fi
}

# ---- Helper: create valid receipt ----
make_receipt() {
    local role="$1"
    local file=".phase_control/delegations/${PHASE}_attempt_${ATTEMPT}_${role}.json"
    local instruction=".phase_control/instructions/${PHASE}_attempt_${ATTEMPT}_${role}.json"
    mkdir -p .phase_control/instructions
    cat > "$instruction" <<EOF
{"phase_id":"$PHASE","role":"$role","created_at":"2026-05-28T13:00:00Z"}
EOF
    local output
    if [ "$role" = "worker" ]; then
        output=".phase_control/evidence/${PHASE}_attempt_${ATTEMPT}.json"
    else
        output=".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json"
    fi
    cat > "$file" <<EOF
{
  "phase_id": "$PHASE",
  "attempt": $ATTEMPT,
  "role": "$role",
  "created_at": "2026-05-28T13:00:00Z",
  "delegated_at": "2026-05-28T13:00:00Z",
  "timestamp": "2026-05-28T13:00:00Z",
  "leader_session_id": "test",
  "delegation_method": "delegate_task",
  "leader_instruction_path": "$instruction",
  "instruction_path": "$instruction",
  "expected_output_path": "$output",
  "delegation_trust_level": "INTENT_ONLY",
  "trust_level": "INTENT_ONLY"
}
EOF
}

# ---- Helper: create valid command log ----
make_cmd_log() {
    local file=".phase_control/logs/${PHASE}_attempt_${ATTEMPT}.commands.jsonl"
    cat > "$file" <<EOF
{"phase_id":"$PHASE","attempt":$ATTEMPT,"command":"echo test","output_tail":"test","exit_code":0,"runner":"hmte exec","started_at":"2026-05-28T13:00:00Z","ended_at":"2026-05-28T13:00:01Z"}
EOF
}

# ---- Helper: create valid evidence ----
make_evidence() {
    cat > ".phase_control/evidence/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"phase_id":"$PHASE","attempt":$ATTEMPT,"status":"completed","generated_at":"2026-05-28T13:01:00Z","timestamp":"2026-05-28T13:01:00Z","commands_run":["echo test"],"files_modified":[],"changed_files":["README.md"],"unresolved_risks":[],"residual_risks":["none"],"command_log_path":".phase_control/logs/${PHASE}_attempt_${ATTEMPT}.commands.jsonl"}
EOF
}

# ---- Helper: sha256 兼容 macOS ----
sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# ---- Helper: create PASS verdict with scorecard ----
make_pass_verdict() {
    local ev_sha
    ev_sha="$(sha256_file ".phase_control/evidence/${PHASE}_attempt_${ATTEMPT}.json")"
    local log_sha
    log_sha="$(sha256_file ".phase_control/logs/${PHASE}_attempt_${ATTEMPT}.commands.jsonl")"
    cat > ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"status":"PASS","phase_id":"$PHASE","attempt":$ATTEMPT,"timestamp":"2026-05-28T13:02:00Z","evidence_sha256":"$ev_sha","command_log_sha256":"$log_sha","adversarial_scorecard":{"criteria_passed":[{"criterion":"test","evidence":"test execution completed and verified through code review"}],"criteria_failed":[],"evidence_paths":[".phase_control/evidence/${PHASE}_attempt_${ATTEMPT}.json",".phase_control/logs/${PHASE}_attempt_${ATTEMPT}.commands.jsonl","README.md"],"residual_risks":["none"],"verification_method":"code_review","risk_disposition":[],"re_verification_conclusion":"All acceptance criteria verified independently through code review and command log analysis","independently_verified_files":["README.md"],"command_log_checked":true,"diff_checked":true,"evidence_consistency_checked":true}}
EOF
}

# ---- Helper: create full valid chain ----
make_full_chain() {
    setup
    make_receipt worker
    make_receipt verifier
    make_cmd_log
    make_evidence
    make_pass_verdict
}

echo "========================================="
echo "Anti-Fake Enforcement E2E Tests"
echo "========================================="
echo "HMTE_STRICT_HASH=${HMTE_STRICT_HASH:-false}"
echo "HMTE_REQUIRE_OBSERVED=${HMTE_REQUIRE_OBSERVED:-false}"
echo ""

# === F1: 缺 worker receipt ===
echo ""
echo "--- F1: 缺 worker receipt ---"
setup
make_receipt verifier
make_cmd_log
make_evidence
make_pass_verdict
if $AUDIT "$PHASE" "$ATTEMPT" --json > /dev/null 2>&1; then
    log_fail "F1: audit should have FAILed (no worker receipt)"
else
    log_pass "F1: audit correctly FAILed (no worker receipt)"
fi

# === F2: 缺 verifier receipt ===
echo ""
echo "--- F2: 缺 verifier receipt ---"
setup
make_receipt worker
make_cmd_log
make_evidence
make_pass_verdict
if $AUDIT "$PHASE" "$ATTEMPT" --json > /dev/null 2>&1; then
    log_fail "F2: audit should have FAILed (no verifier receipt)"
else
    log_pass "F2: audit correctly FAILed (no verifier receipt)"
fi

# === F3: Worker 没用 hmte exec ===
echo ""
echo "--- F3: command log runner != hmte exec ---"
setup
make_receipt worker
make_receipt verifier
cat > ".phase_control/logs/${PHASE}_attempt_${ATTEMPT}.commands.jsonl" <<EOF
{"phase_id":"$PHASE","attempt":$ATTEMPT,"command":"echo test","exit_code":0,"runner":"terminal","started_at":"2026-05-28T13:00:00Z","ended_at":"2026-05-28T13:00:01Z"}
EOF
make_evidence
make_pass_verdict
if $AUDIT "$PHASE" "$ATTEMPT" --json > /dev/null 2>&1; then
    log_fail "F3: audit should have FAILed (runner=terminal)"
else
    log_pass "F3: audit correctly FAILed (runner=terminal)"
fi

# === F4: PASS verdict 无 scorecard ===
echo ""
echo "--- F4: PASS verdict 无 scorecard ---"
setup
make_receipt worker
make_receipt verifier
make_cmd_log
make_evidence
cat > ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"status":"PASS","phase_id":"$PHASE","attempt":$ATTEMPT,"timestamp":"2026-05-28T13:02:00Z"}
EOF
if $GATE "$PHASE" --attempt "$ATTEMPT" > /dev/null 2>&1; then
    log_fail "F4: gate should have BLOCKED (no scorecard)"
else
    log_pass "F4: gate correctly BLOCKED (no scorecard)"
fi

# === F5: scorecard criteria_passed 为空 ===
echo ""
echo "--- F5: scorecard criteria_passed 为空 ---"
setup
make_receipt worker
make_receipt verifier
make_cmd_log
make_evidence
cat > ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"status":"PASS","phase_id":"$PHASE","attempt":$ATTEMPT,"timestamp":"2026-05-28T13:02:00Z","adversarial_scorecard":{"criteria_passed":[],"criteria_failed":[],"evidence_paths":["x"],"residual_risks":["none"],"re_verification_conclusion":"ok"}}
EOF
if $GATE "$PHASE" --attempt "$ATTEMPT" > /dev/null 2>&1; then
    log_fail "F5: gate should have BLOCKED (empty criteria_passed)"
else
    log_pass "F5: gate correctly BLOCKED (empty criteria_passed)"
fi

# === F6: PASS verdict 有 criteria_failed ===
echo ""
echo "--- F6: PASS verdict 有 criteria_failed ---"
setup
make_receipt worker
make_receipt verifier
make_cmd_log
make_evidence
cat > ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"status":"PASS","phase_id":"$PHASE","attempt":$ATTEMPT,"timestamp":"2026-05-28T13:02:00Z","adversarial_scorecard":{"criteria_passed":[{"criterion":"a","evidence":"x"}],"criteria_failed":[{"criterion":"b","reason":"not done"}],"evidence_paths":["x"],"residual_risks":["none"],"re_verification_conclusion":"ok"}}
EOF
if $GATE "$PHASE" --attempt "$ATTEMPT" > /dev/null 2>&1; then
    log_fail "F6: gate should have BLOCKED (PASS with criteria_failed)"
else
    log_pass "F6: gate correctly BLOCKED (PASS with criteria_failed)"
fi

# === F7: 时间线倒序 ===
echo ""
echo "--- F7: 时间线倒序 ---"
setup
make_receipt worker
make_receipt verifier
make_cmd_log
cat > ".phase_control/evidence/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"phase_id":"$PHASE","attempt":$ATTEMPT,"status":"completed","timestamp":"2026-05-28T13:10:00Z"}
EOF
cat > ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json" <<EOF
{"status":"PASS","phase_id":"$PHASE","attempt":$ATTEMPT,"timestamp":"2026-05-28T13:05:00Z","adversarial_scorecard":{"criteria_passed":[{"criterion":"test","evidence":"x"}],"criteria_failed":[],"evidence_paths":["x"],"residual_risks":["none"],"re_verification_conclusion":"ok"}}
EOF
if $AUDIT "$PHASE" "$ATTEMPT" --json > /dev/null 2>&1; then
    log_fail "F7: audit should have FAILed (timeline inverted)"
else
    log_pass "F7: audit correctly FAILed (timeline inverted)"
fi

# === F8: phase_id 路径穿越 ===
echo ""
echo "--- F8: phase_id 路径穿越 ---"
if $AUDIT "../../evil" "$ATTEMPT" --json > /dev/null 2>&1; then
    log_fail "F8: audit should have rejected path traversal"
else
    log_pass "F8: audit correctly rejected path traversal"
fi

# === F9: 关键阶段要求 OBSERVED ===
echo ""
echo "--- F9: critical phase requires OBSERVED ---"
PHASE="p0_critical"
ATTEMPT=1
make_full_chain
if HMTE_REQUIRE_OBSERVED=true $GATE "$PHASE" > /dev/null 2>&1; then
    log_fail "F9: gate should have BLOCKED critical phase with INTENT_ONLY"
else
    log_pass "F9: gate correctly BLOCKED critical phase with INTENT_ONLY"
fi

# === F10: strict hash 缺 sha256 必须 BLOCKED ===
echo ""
echo "--- F10: strict hash missing sha256 ---"
PHASE="test_anti_fake"
ATTEMPT=1
setup
make_receipt worker
make_receipt verifier
make_cmd_log
make_evidence
# 关键：verdict 是合法 JSON，但没有 sha256 字段
cat > ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json" <<'EOF'
{
  "status": "PASS",
  "phase_id": "test_anti_fake",
  "attempt": 1,
  "timestamp": "2026-05-28T13:02:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [{"criterion": "test", "evidence": "test execution completed and verified through code review"}],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/test_anti_fake_attempt_1.json",".phase_control/logs/test_anti_fake_attempt_1.commands.jsonl","README.md"],
    "residual_risks": ["none"],
    "verification_method": "code_review",
    "risk_disposition": [],
    "re_verification_conclusion": "All acceptance criteria verified independently through code review and command log analysis",
    "independently_verified_files": ["README.md"],
    "command_log_checked": true,
    "diff_checked": true,
    "evidence_consistency_checked": true
  }
}
EOF
# 验证 verdict 是合法 JSON
validate_json_file ".phase_control/verdicts/${PHASE}_attempt_${ATTEMPT}.json"
# 在 strict hash 模式下应被 BLOCKED
if HMTE_STRICT_HASH=true $GATE "$PHASE" > /dev/null 2>&1; then
    log_fail "F10: gate should have BLOCKED missing sha256 in strict mode"
else
    log_pass "F10: gate correctly BLOCKED missing sha256 in strict mode"
fi

# === P1: 完整链路 PASS ===
echo ""
echo "--- P1: full chain normal ---"
make_full_chain
if $GATE "$PHASE" --attempt "$ATTEMPT" > /dev/null 2>&1; then
    log_pass "P1: gate correctly PASSed (full chain)"
else
    log_fail "P1: gate should have PASSed (full chain)"
fi

# === P2: strict hash 完整链路 PASS ===
echo ""
echo "--- P2: full chain strict hash ---"
make_full_chain
if HMTE_STRICT_HASH=true $GATE "$PHASE" > /dev/null 2>&1; then
    log_pass "P2: gate correctly PASSed with strict hash"
else
    log_fail "P2: gate should have PASSed with strict hash"
fi

# === Summary ===
echo ""
echo "========================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "========================================="
[ $FAIL_COUNT -eq 0 ] && exit 0 || exit 1
