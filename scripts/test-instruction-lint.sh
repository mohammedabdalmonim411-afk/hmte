#!/usr/bin/env bash
# test-instruction-lint.sh — HTE v1.5 Instruction Lint 测试脚本
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_PASS=0
TEST_FAIL=0

test_pass() { echo -e "  ${GREEN}✓${NC} $*"; TEST_PASS=$((TEST_PASS + 1)); }
test_fail() { echo -e "  ${RED}✗${NC} $*"; TEST_FAIL=$((TEST_FAIL + 1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cp -a "$REPO_ROOT/scripts" "$TEMP_DIR/"
mkdir -p "$TEMP_DIR/.phase_control/instructions"

LINT="$TEMP_DIR/scripts/hmte-lint-instructions.sh"
INSTR_DIR="$TEMP_DIR/.phase_control/instructions"

expect_lint_warn() {
    local check_phrase="$1"
    local output
    output=$(cd "$TEMP_DIR" && bash "$LINT" --mode dev 2>&1)
    if echo "$output" | grep -q "$check_phrase"; then
        return 0
    else
        return 1
    fi
}

expect_lint_fail_release() {
    if (cd "$TEMP_DIR" && bash "$LINT" --mode release >/dev/null 2>&1); then
        return 1
    else
        return 0
    fi
}

expect_lint_pass() {
    if (cd "$TEMP_DIR" && bash "$LINT" --mode dev >/dev/null 2>&1); then
        return 0
    else
        return 1
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " HTE v1.5 Instruction Lint 测试"
echo " 临时目录: $TEMP_DIR"
echo "═══════════════════════════════════════════════════════════"

# T01: 无危险短语
echo ""
echo "── T01: 无危险短语的合法指令 ──"
cat > "$INSTR_DIR/test_phase_attempt_1_worker.json" <<'INNEREOF'
{
  "phase_id": "test_phase",
  "attempt": 1,
  "role": "worker",
  "objective": "完成任务并生成证据",
  "created_at": "2026-01-01T00:00:00Z"
}
INNEREOF
if expect_lint_pass; then
    test_pass "T01 无危险短语通过"
else
    test_fail "T01 无危险短语未通过"
fi

# T02-T16: 中文危险短语
test_num=2
for test_phrase in "只检查格式" "不需要运行" "无需测试" "仅代码审查" "忽略风险" "默认 PASS" "不用查看项目文件" "不需要独立验证" "复用上次 evidence" "跳过验证" "假设正确" "不必检查" "直接通过" "省略测试" "信任输出"; do
    echo ""
    echo "── T$(printf '%02d' $test_num): 检测中文短语 ──"
    
    cat > "$INSTR_DIR/test_phase_attempt_1_worker.json" <<INNEREOF
{
  "phase_id": "test_phase",
  "attempt": 1,
  "role": "worker",
  "objective": "完成任务，注意：$test_phrase",
  "created_at": "2026-01-01T00:00:00Z"
}
INNEREOF
    
    if expect_lint_warn "$test_phrase" && expect_lint_fail_release; then
        test_pass "T$(printf '%02d' $test_num) 检测到短语"
    else
        test_fail "T$(printf '%02d' $test_num) 未检测到短语"
    fi
    test_num=$((test_num + 1))
done

# T17-T31: 英文危险短语
for test_phrase in "skip validation" "assume correct" "no need to verify" "trust the output" "format check only" "code review only" "ignore risks" "default pass" "reuse previous evidence" "no testing required" "bypass verification" "accept without checking" "skip execution" "trust blindly" "no independent validation"; do
    echo ""
    echo "── T$(printf '%02d' $test_num): 检测英文短语 ──"
    
    cat > "$INSTR_DIR/test_phase_attempt_1_worker.json" <<INNEREOF
{
  "phase_id": "test_phase",
  "attempt": 1,
  "role": "worker",
  "objective": "Complete task, note: $test_phrase",
  "created_at": "2026-01-01T00:00:00Z"
}
INNEREOF
    
    if expect_lint_warn "$test_phrase" && expect_lint_fail_release; then
        test_pass "T$(printf '%02d' $test_num) 检测到短语"
    else
        test_fail "T$(printf '%02d' $test_num) 未检测到短语"
    fi
    test_num=$((test_num + 1))
done

# T32: explicit_allow_weak_validation 允许危险短语
echo ""
echo "── T32: explicit_allow_weak_validation 允许危险短语 ──"
cat > "$INSTR_DIR/test_phase_attempt_1_worker.json" <<'INNEREOF'
{
  "phase_id": "test_phase",
  "attempt": 1,
  "role": "worker",
  "objective": "跳过验证",
  "explicit_allow_weak_validation": true,
  "reason": "这是一个特殊场景，需要跳过验证以加快开发速度",
  "created_at": "2026-01-01T00:00:00Z"
}
INNEREOF

if (cd "$TEMP_DIR" && bash "$LINT" --mode release >/dev/null 2>&1); then
    test_pass "T32 explicit_allow_weak_validation 允许危险短语"
else
    test_fail "T32 explicit_allow_weak_validation 未生效"
fi

# T33: explicit_allow_weak_validation 但缺 reason
echo ""
echo "── T33: explicit_allow_weak_validation 但缺 reason ──"
cat > "$INSTR_DIR/test_phase_attempt_1_worker.json" <<'INNEREOF'
{
  "phase_id": "test_phase",
  "attempt": 1,
  "role": "worker",
  "objective": "跳过验证",
  "explicit_allow_weak_validation": true,
  "created_at": "2026-01-01T00:00:00Z"
}
INNEREOF

if (cd "$TEMP_DIR" && bash "$LINT" --mode release >/dev/null 2>&1); then
    test_fail "T33 缺 reason 应该失败"
else
    test_pass "T33 缺 reason 正确失败"
fi

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
