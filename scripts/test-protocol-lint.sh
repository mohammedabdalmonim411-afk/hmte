#!/usr/bin/env bash
# test-protocol-lint.sh — TAF 协议检查测试脚本
# 验证 hmte-lint-protocol.sh 的关键规则不会误报、不会漏报
# 覆盖 T01-T17 共 17 个测试用例
set -euo pipefail

# ─── 颜色 ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TEST_PASS=0
TEST_FAIL=0

test_pass() { echo -e "  ${GREEN}✓${NC} $*"; TEST_PASS=$((TEST_PASS + 1)); }
test_fail() { echo -e "  ${RED}✗${NC} $*"; TEST_FAIL=$((TEST_FAIL + 1)); }

# ─── 隔离环境 ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp -a "$REPO_ROOT/scripts" "$TEMP_DIR/"
cp -a "$REPO_ROOT/src" "$TEMP_DIR/"
[ -f "$REPO_ROOT/README.md" ] && cp -a "$REPO_ROOT/README.md" "$TEMP_DIR/"
[ -f "$REPO_ROOT/HERMES.md" ] && cp -a "$REPO_ROOT/HERMES.md" "$TEMP_DIR/"
[ -f "$REPO_ROOT/CHANGELOG.md" ] && cp -a "$REPO_ROOT/CHANGELOG.md" "$TEMP_DIR/"
[ -f "$REPO_ROOT/CONTRIBUTING.md" ] && cp -a "$REPO_ROOT/CONTRIBUTING.md" "$TEMP_DIR/"
[ -f "$REPO_ROOT/docs/HTE_PROTOCOL.md" ] && mkdir -p "$TEMP_DIR/docs" && cp -a "$REPO_ROOT/docs/HTE_PROTOCOL.md" "$TEMP_DIR/docs/"

# 手工创建空运行时目录
mkdir -p "$TEMP_DIR/.phase_control"/{instructions,evidence,verdicts,logs,delegations,errors,pids,traces}

LINT="$TEMP_DIR/scripts/hmte-lint-protocol.sh"
PC="$TEMP_DIR/.phase_control"

# ══════════════════════════════════════════════════════════════════
# Helper 函数
# ══════════════════════════════════════════════════════════════════

# ─── reset_runtime_fixture ──────────────────────────────────────
# 清空运行时目录中的文件（保留目录结构）
reset_runtime_fixture() {
    for subdir in instructions evidence verdicts logs delegations errors pids traces; do
        rm -rf "$PC/$subdir"
        mkdir -p "$PC/$subdir"
    done
    rm -f "$PC/phases.json" "$PC/session.json" "$PC/state.json"
    rm -rf "$TEMP_DIR/.hmte"
}

# ─── create_valid_runtime_fixture ──────────────────────────────
# 构造最小合法运行时文件
create_valid_runtime_fixture() {
    reset_runtime_fixture

    # phases.json
    cat > "$PC/phases.json" <<'EOF'
{
  "phases": [
    {
      "phase_id": "phase_1",
      "name": "Test Phase",
      "objective": "Test objective",
      "acceptance_criteria": ["criterion 1"],
      "required_evidence": ["evidence 1"]
    }
  ]
}
EOF

    # session.json
    cat > "$PC/session.json" <<'EOF'
{
  "workflow": "TAF",
  "mode": "file-instruction",
  "task": "test task",
  "status": "KICKED_OFF",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF

    # instructions
    cat > "$PC/instructions/phase_1_attempt_1_worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "objective": "do work",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF

    cat > "$PC/instructions/phase_1_attempt_1_verifier.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "verifier",
  "objective": "verify work",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF

    # delegations
    cat > "$PC/delegations/phase_1_attempt_1_worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_worker.json",
  "expected_output_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF

    cat > "$PC/delegations/phase_1_attempt_1_verifier.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "verifier",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_verifier.json",
  "expected_output_path": ".phase_control/verdicts/phase_1_attempt_1.json",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF

    # command log
    cat > "$PC/logs/phase_1_attempt_1.commands.jsonl" <<'EOF'
{"phase_id":"phase_1","attempt":1,"command":"echo test","exit_code":0,"runner":"hmte exec","started_at":"2026-01-01T00:00:00Z","ended_at":"2026-01-01T00:01:00Z","output_tail":"test output"}
EOF

    # evidence
    cat > "$PC/evidence/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "generated_at": "2026-01-01T00:01:00Z",
  "command_log_path": ".phase_control/logs/phase_1_attempt_1.commands.jsonl",
  "commands_run": ["echo test"],
  "changed_files": [],
  "unresolved_risks": []
}
EOF

    # verdict (PASS with adversarial_scorecard)
    cat > "$PC/verdicts/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-01-01T00:02:00Z",
  "adversarial_scorecard": {
    "criteria_passed": ["criterion 1"],
    "criteria_failed": [],
    "evidence_paths": [
      ".phase_control/evidence/phase_1_attempt_1.json",
      ".phase_control/logs/phase_1_attempt_1.commands.jsonl"
    ],
    "residual_risks": []
  }
}
EOF

    # team-rules.md
    mkdir -p "$TEMP_DIR/.hmte"
    cat > "$TEMP_DIR/.hmte/team-rules.md" <<'EOF'
# Team Rules
placeholder
EOF
}

# ─── expect_lint_pass ─────────────────────────────────────────
expect_lint_pass() {
    if bash "$LINT" -d "$TEMP_DIR" >/dev/null 2>&1; then
        echo "PASS: lint passed as expected"
    else
        echo "FAIL: expected lint PASS but got failure"
        exit 1
    fi
}

# ─── expect_lint_fail ─────────────────────────────────────────
expect_lint_fail() {
    if bash "$LINT" -d "$TEMP_DIR" >/dev/null 2>&1; then
        echo "FAIL: expected lint failure but got PASS"
        exit 1
    else
        echo "PASS: lint failed as expected"
    fi
}

# ══════════════════════════════════════════════════════════════════
# 主测试
# ══════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " TAF 协议检查测试 (T01-T17)"
echo " 临时目录: $TEMP_DIR"
echo "═══════════════════════════════════════════════════════════"

# ─── T01: 合法最小运行时 → expect_lint_pass ───────────────────
echo ""
echo "── T01: 合法最小运行时 ──"
create_valid_runtime_fixture
if expect_lint_pass; then
    test_pass "T01 合法最小运行时通过"
else
    test_fail "T01 合法最小运行时未通过"
fi

# ─── T02: 缺 phases.json → expect_lint_fail ──────────────────
echo ""
echo "── T02: 缺 phases.json ──"
create_valid_runtime_fixture
rm -f "$PC/phases.json"
if expect_lint_fail; then
    test_pass "T02 缺 phases.json 正确失败"
else
    test_fail "T02 缺 phases.json 未失败"
fi

# ─── T03: phase 缺 phase_id 和 id → expect_lint_fail ────────
echo ""
echo "── T03: phase 缺 phase_id 和 id ──"
create_valid_runtime_fixture
cat > "$PC/phases.json" <<'EOF'
{
  "phases": [
    {
      "name": "Test Phase",
      "objective": "Test objective"
    }
  ]
}
EOF
if expect_lint_fail; then
    test_pass "T03 缺 phase_id/id 正确失败"
else
    test_fail "T03 缺 phase_id/id 未失败"
fi

# ─── T04: PASS verdict 缺 adversarial_scorecard → expect_lint_fail
echo ""
echo "── T04: PASS verdict 缺 adversarial_scorecard ──"
create_valid_runtime_fixture
cat > "$PC/verdicts/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-01-01T00:02:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T04 缺 adversarial_scorecard 正确失败"
else
    test_fail "T04 缺 adversarial_scorecard 未失败"
fi

# ─── T05: PASS verdict criteria_failed 非空 → expect_lint_fail
echo ""
echo "── T05: PASS verdict criteria_failed 非空 ──"

# T05a: criteria_failed 在顶层
create_valid_runtime_fixture
cat > "$PC/verdicts/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-01-01T00:02:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [],
    "criteria_failed": ["some failure"],
    "evidence_paths": [".phase_control/evidence/phase_1_attempt_1.json"],
    "residual_risks": []
  }
}
EOF
if expect_lint_fail; then
    test_pass "T05a criteria_failed 在 scorecard 内非空正确失败"
else
    test_fail "T05a criteria_failed 在 scorecard 内非空未失败"
fi

# T05b: criteria_failed 在顶层
create_valid_runtime_fixture
cat > "$PC/verdicts/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-01-01T00:02:00Z",
  "criteria_failed": ["top-level failure"],
  "adversarial_scorecard": {
    "criteria_passed": [],
    "criteria_failed": [],
    "evidence_paths": [".phase_control/evidence/phase_1_attempt_1.json"],
    "residual_risks": []
  }
}
EOF
if expect_lint_fail; then
    test_pass "T05b criteria_failed 在顶层非空正确失败"
else
    test_fail "T05b criteria_failed 在顶层非空未失败"
fi

# ─── T06: PASS verdict 缺 evidence_paths → expect_lint_fail
echo ""
echo "── T06: PASS verdict 缺 evidence_paths ──"

# T06a: 完全没有 evidence_paths
create_valid_runtime_fixture
cat > "$PC/verdicts/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-01-01T00:02:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [],
    "criteria_failed": [],
    "residual_risks": []
  }
}
EOF
if expect_lint_fail; then
    test_pass "T06a 缺 evidence_paths 正确失败"
else
    test_fail "T06a 缺 evidence_paths 未失败"
fi

# T06b: evidence_paths 为空数组
create_valid_runtime_fixture
cat > "$PC/verdicts/phase_1_attempt_1.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "status": "PASS",
  "timestamp": "2026-01-01T00:02:00Z",
  "adversarial_scorecard": {
    "criteria_passed": [],
    "criteria_failed": [],
    "evidence_paths": [],
    "residual_risks": []
  }
}
EOF
if expect_lint_fail; then
    test_pass "T06b evidence_paths 为空数组正确失败"
else
    test_fail "T06b evidence_paths 为空数组未失败"
fi

# ─── T07: OBSERVED 缺 tool_call_trace_path → expect_lint_fail
echo ""
echo "── T07: OBSERVED 缺 tool_call_trace_path ──"
create_valid_runtime_fixture
cat > "$PC/delegations/phase_1_attempt_1_worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "OBSERVED",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_worker.json",
  "expected_output_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "observed_delegate_task_id": "task_123",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T07 OBSERVED 缺 tool_call_trace_path 正确失败"
else
    test_fail "T07 OBSERVED 缺 tool_call_trace_path 未失败"
fi

# ─── T08: OBSERVED 缺 observed_delegate_task_id → expect_lint_fail
echo ""
echo "── T08: OBSERVED 缺 observed_delegate_task_id ──"
create_valid_runtime_fixture
cat > "$PC/delegations/phase_1_attempt_1_worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "OBSERVED",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_worker.json",
  "expected_output_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "tool_call_trace_path": ".phase_control/traces/phase_1_attempt_1_worker.trace.json",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
# 创建 trace 文件以免文件不存在干扰
cat > "$PC/traces/phase_1_attempt_1_worker.trace.json" <<'EOF'
{"entries": []}
EOF
if expect_lint_fail; then
    test_pass "T08 OBSERVED 缺 observed_delegate_task_id 正确失败"
else
    test_fail "T08 OBSERVED 缺 observed_delegate_task_id 未失败"
fi

# ─── T09: OBSERVED tool_call_trace_path 指向不存在文件 → expect_lint_fail
echo ""
echo "── T09: OBSERVED tool_call_trace_path 指向不存在文件 ──"
create_valid_runtime_fixture
# 确保 trace 文件不存在
rm -f "$PC/traces/phase_1_attempt_1_worker.trace.json"
cat > "$PC/delegations/phase_1_attempt_1_worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "OBSERVED",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_worker.json",
  "expected_output_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "tool_call_trace_path": ".phase_control/traces/phase_1_attempt_1_worker.trace.json",
  "observed_delegate_task_id": "task_123",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T09 trace 文件不存在正确失败"
else
    test_fail "T09 trace 文件不存在未失败"
fi

# ─── T10: OBSERVED 使用 command log 冒充 trace → expect_lint_fail
echo ""
echo "── T10: OBSERVED 使用 command log 冒充 trace ──"
create_valid_runtime_fixture
cat > "$PC/traces/phase_1_attempt_1_worker.trace.json" <<'EOF'
{"entries": []}
EOF
cat > "$PC/delegations/phase_1_attempt_1_worker.json" <<EOF
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "OBSERVED",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_worker.json",
  "expected_output_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "tool_call_trace_path": ".phase_control/logs/phase_1_attempt_1.commands.jsonl",
  "command_log_path": ".phase_control/logs/phase_1_attempt_1.commands.jsonl",
  "observed_delegate_task_id": "task_123",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T10 trace == command_log 正确失败"
else
    test_fail "T10 trace == command_log 未失败"
fi

# ─── T11: worker expected_output_path 指向 verdicts → expect_lint_fail
echo ""
echo "── T11: worker expected_output_path 指向 verdicts ──"
create_valid_runtime_fixture
cat > "$PC/delegations/phase_1_attempt_1_worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_worker.json",
  "expected_output_path": ".phase_control/verdicts/phase_1_attempt_1.json",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T11 worker expected_output_path 指向 verdicts 正确失败"
else
    test_fail "T11 worker expected_output_path 指向 verdicts 未失败"
fi

# ─── T12: verifier expected_output_path 指向 evidence → expect_lint_fail
echo ""
echo "── T12: verifier expected_output_path 指向 evidence ──"
create_valid_runtime_fixture
cat > "$PC/delegations/phase_1_attempt_1_verifier.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "verifier",
  "delegation_trust_level": "INTENT_ONLY",
  "delegation_method": "delegate_task",
  "leader_instruction_path": ".phase_control/instructions/phase_1_attempt_1_verifier.json",
  "expected_output_path": ".phase_control/evidence/phase_1_attempt_1.json",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T12 verifier expected_output_path 指向 evidence 正确失败"
else
    test_fail "T12 verifier expected_output_path 指向 evidence 未失败"
fi

# ─── T13: command log 缺 started_at → expect_lint_fail
echo ""
echo "── T13: command log 缺 started_at ──"
create_valid_runtime_fixture
cat > "$PC/logs/phase_1_attempt_1.commands.jsonl" <<'EOF'
{"phase_id":"phase_1","attempt":1,"command":"echo test","exit_code":0,"runner":"hmte exec","ended_at":"2026-01-01T00:01:00Z","output_tail":"test output"}
EOF
if expect_lint_fail; then
    test_pass "T13 command log 缺 started_at 正确失败"
else
    test_fail "T13 command log 缺 started_at 未失败"
fi

# ─── T14: command log 缺 output_tail → expect_lint_fail
echo ""
echo "── T14: command log 缺 output_tail ──"
create_valid_runtime_fixture
cat > "$PC/logs/phase_1_attempt_1.commands.jsonl" <<'EOF'
{"phase_id":"phase_1","attempt":1,"command":"echo test","exit_code":0,"runner":"hmte exec","started_at":"2026-01-01T00:00:00Z","ended_at":"2026-01-01T00:01:00Z"}
EOF
if expect_lint_fail; then
    test_pass "T14 command log 缺 output_tail 正确失败"
else
    test_fail "T14 command log 缺 output_tail 未失败"
fi

# ─── T15: 错误 instruction 命名 → expect_lint_fail
echo ""
echo "── T15: 错误 instruction 命名 (phase-1-worker.json) ──"
create_valid_runtime_fixture
rm -f "$PC/instructions/phase_1_attempt_1_worker.json"
rm -f "$PC/instructions/phase_1_attempt_1_verifier.json"
cat > "$PC/instructions/phase-1-worker.json" <<'EOF'
{
  "phase_id": "phase_1",
  "attempt": 1,
  "role": "worker",
  "created_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T15 错误 instruction 命名正确失败"
else
    test_fail "T15 错误 instruction 命名未失败"
fi

# ─── T16: 错误 final_audit 命名 → expect_lint_fail
echo ""
echo "── T16: 错误 final_audit 命名 (final_audit_attempt_1.evidence.json) ──"
create_valid_runtime_fixture
# 在 evidence 目录创建错误命名的 final_audit 文件
cat > "$PC/evidence/final_audit_attempt_1.evidence.json" <<'EOF'
{
  "phase_id": "final_audit",
  "attempt": 1,
  "generated_at": "2026-01-01T00:00:00Z"
}
EOF
if expect_lint_fail; then
    test_pass "T16 错误 final_audit 命名正确失败"
else
    test_fail "T16 错误 final_audit 命名未失败"
fi

# ─── T17: legacy .hmte/team-rules.md 仅兼容，docs/HTE_PROTOCOL.md 才是规范来源 ─────────────────────────────
echo ""
echo "── T17: legacy .hmte/team-rules.md 仅兼容，docs/HTE_PROTOCOL.md 才是规范来源 ──"

# T17a: dev 模式 → docs 存在且 legacy 缺失时，lint 仍应通过
create_valid_runtime_fixture
rm -rf "$TEMP_DIR/.hmte"
if bash "$LINT" -d "$TEMP_DIR" >/dev/null 2>&1; then
    test_pass "T17a dev 模式 docs/HTE_PROTOCOL.md 通过且 legacy 可选"
else
    test_fail "T17a dev 模式 docs/HTE_PROTOCOL.md 应该通过"
fi

# T17b: release 模式 → docs 存在且 legacy 缺失时，lint 仍应通过
rm -rf "$TEMP_DIR/.hmte"
if HMTE_LINT_MODE=release bash "$LINT" -d "$TEMP_DIR" >/dev/null 2>&1; then
    test_pass "T17b release 模式 docs/HTE_PROTOCOL.md 通过且 legacy 可选"
else
    test_fail "T17b release 模式 docs/HTE_PROTOCOL.md 不应失败"
fi

# ══════════════════════════════════════════════════════════════════
# 汇总
# ══════════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════"
TOTAL=$((TEST_PASS + TEST_FAIL))
if [ "$TEST_FAIL" -gt 0 ]; then
    echo -e " ${RED}结果: $TEST_PASS/$TOTAL 通过, $TEST_FAIL 失败${NC}"
    echo "═══════════════════════════════════════════════════════════"
    exit 1
else
    echo -e " ${GREEN}结果: $TEST_PASS/$TOTAL 全部通过${NC}"
    echo "═══════════════════════════════════════════════════════════"
    exit 0
fi
