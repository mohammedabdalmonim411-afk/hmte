#!/usr/bin/env bash
# hmte-doctor.sh - TAF legacy hmte 轻量自检（只诊断，不修复）
#
# 检查项：
#   1. git repo 存在
#   2. bash 可用
#   3. python3 可用
#   4. TAF legacy hmte scripts 完整性
#   5. .phase_control 目录结构
#
# 用法：
#   bash scripts/hmte-doctor.sh

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*"; }

# 统计变量
TOTAL_CHECKS=0
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check() {
    local name="$1"
    local condition="$2"
    local detail="${3:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if eval "$condition"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        if [ -n "$detail" ]; then
            success "$name: $detail"
        else
            success "$name"
        fi
        return 0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        if [ -n "$detail" ]; then
            error "$name: $detail"
        else
            error "$name"
        fi
        return 1
    fi
}

warn_check() {
    local name="$1"
    local condition="$2"
    local detail="${3:-}"

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    if eval "$condition"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        success "$name"
    else
        WARN_COUNT=$((WARN_COUNT + 1))
        if [ -n "$detail" ]; then
            warn "$name: $detail"
        else
            warn "$name"
        fi
    fi
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 TAF Doctor - 轻量自检"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# 1. 检查 git repo
# ============================================================
info "检查 git repo..."
check "git repo 存在" "[ -d .git ]" "$(pwd)/.git"

if [ -d .git ]; then
    # 检查 git 状态
    if git rev-parse --git-dir >/dev/null 2>&1; then
        success "git repo 有效"
        PASS_COUNT=$((PASS_COUNT + 1))
        
        # 显示当前分支
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        info "  当前分支: $CURRENT_BRANCH"
        
        # 显示最近一次提交
        LAST_COMMIT=$(git log -1 --oneline 2>/dev/null || echo "no commits")
        info "  最近提交: $LAST_COMMIT"
    else
        error "git repo 损坏"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi
echo ""

# ============================================================
# 2. 检查 bash
# ============================================================
info "检查 bash..."
check "bash 可执行" "command -v bash >/dev/null 2>&1"

if command -v bash >/dev/null 2>&1; then
    BASH_VERSION_INFO=$(bash --version | head -1)
    success "bash 版本: $BASH_VERSION_INFO"
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi
echo ""

# ============================================================
# 3. 检查 python3
# ============================================================
info "检查 python3..."
check "python3 可执行" "command -v python3 >/dev/null 2>&1"

if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    success "python3 版本: $PYTHON_VERSION"
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    # 检查必需的 Python 模块
    info "  检查 Python 模块..."
    for module in json sys os pathlib datetime hashlib; do
        if python3 -c "import $module" 2>/dev/null; then
            success "    模块 $module 可用"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "    模块 $module 不可用"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    done
fi
echo ""

# ============================================================
# 4. 检查 TAF legacy hmte scripts 完整性
# ============================================================
info "检查 TAF legacy hmte scripts 完整性..."

# 核心脚本列表
CORE_SCRIPTS=(
    "hmte-exec.sh"
    "hmte-init.sh"
    "hmte-kickoff.sh"
    "hmte-final-check.sh"
    "hmte-goal-lock.sh"
    "hmte-lint-instructions.sh"
    "hmte-verify-claims.sh"
    "hmte-leader-jail.sh"
)

for script in "${CORE_SCRIPTS[@]}"; do
    check "  $script 存在" "[ -f scripts/$script ]"
    
    if [ -f "scripts/$script" ]; then
        # 检查可执行权限
        if [ -x "scripts/$script" ]; then
            success "    $script 可执行"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            warn "    $script 不可执行"
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        
        # 检查语法
        if bash -n "scripts/$script" 2>/dev/null; then
            success "    $script 语法正确"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "    $script 语法错误"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
done

# 统计所有脚本
TOTAL_SCRIPTS=$(find scripts -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
info "  总计 $TOTAL_SCRIPTS 个脚本文件"
echo ""

# ============================================================
# 5. 检查 .phase_control 目录结构
# ============================================================
info "检查 .phase_control 目录结构..."
check ".phase_control 目录存在" "[ -d .phase_control ]"

if [ -d .phase_control ]; then
    # 检查必需的子目录
    REQUIRED_DIRS=(
        "evidence"
        "verdicts"
        "logs"
        "instructions"
        "delegations"
        "pids"
        "traces"
        "state"
        "amendments"
        "errors"
    )
    
    for dir in "${REQUIRED_DIRS[@]}"; do
        check "  .phase_control/$dir 存在" "[ -d .phase_control/$dir ]"
    done
    
    # 检查必需的文件
    info "  检查核心文件..."
    check "  session.json 存在" "[ -f .phase_control/session.json ]"
    check "  phases.json 存在" "[ -f .phase_control/phases.json ]"
    check "  state.json 存在" "[ -f .phase_control/state.json ]"
    
    # 检查 JSON 文件格式
    if [ -f .phase_control/session.json ]; then
        if python3 -c "import json; json.load(open('.phase_control/session.json'))" 2>/dev/null; then
            success "  session.json 格式正确"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "  session.json 格式错误"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
    
    if [ -f .phase_control/phases.json ]; then
        if python3 -c "import json; json.load(open('.phase_control/phases.json'))" 2>/dev/null; then
            success "  phases.json 格式正确"
            PASS_COUNT=$((PASS_COUNT + 1))
            
            # 统计 phase 数量
            PHASE_COUNT=$(python3 -c "import json; data=json.load(open('.phase_control/phases.json')); print(len(data.get('phases', [])))" 2>/dev/null || echo "0")
            info "    定义了 $PHASE_COUNT 个 phase"
        else
            error "  phases.json 格式错误"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
    
    if [ -f .phase_control/state.json ]; then
        if python3 -c "import json; json.load(open('.phase_control/state.json'))" 2>/dev/null; then
            success "  state.json 格式正确"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "  state.json 格式错误"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
    
    # 检查 goal_lock.json（可选）
    if [ -f .phase_control/goal_lock.json ]; then
        if python3 -c "import json; json.load(open('.phase_control/goal_lock.json'))" 2>/dev/null; then
            success "  goal_lock.json 存在且格式正确"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            warn "  goal_lock.json 格式错误"
            WARN_COUNT=$((WARN_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    else
        info "  goal_lock.json 不存在（可选）"
    fi
    
    # 统计文件数量
    EVIDENCE_COUNT=$(find .phase_control/evidence -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    VERDICT_COUNT=$(find .phase_control/verdicts -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    LOG_COUNT=$(find .phase_control/logs -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
    
    info "  统计: $EVIDENCE_COUNT 个 evidence, $VERDICT_COUNT 个 verdict, $LOG_COUNT 个 log"

    # 检查 run ledger
    info "  检查 run ledger..."
    if [ -f .phase_control/run_ledger.jsonl ]; then
        # 检查 JSONL 格式
        LEDGER_LINES=$(wc -l < .phase_control/run_ledger.jsonl | tr -d ' ')
        VALID_LINES=0
        INVALID_LINES=0

        while IFS= read -r line; do
            if [ -n "$line" ]; then
                if python3 -c "import json,sys; json.loads(sys.argv[1])" "$line" 2>/dev/null; then
                    VALID_LINES=$((VALID_LINES + 1))
                else
                    INVALID_LINES=$((INVALID_LINES + 1))
                fi
            fi
        done < .phase_control/run_ledger.jsonl

        if [ "$INVALID_LINES" -eq 0 ]; then
            success "  run_ledger.jsonl 格式正确 ($VALID_LINES 条事件)"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            error "  run_ledger.jsonl 有 $INVALID_LINES 条损坏记录"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

        # 检查最近事件时间
        LAST_EVENT_TIME=$(tail -n 1 .phase_control/run_ledger.jsonl | python3 -c "import json,sys; print(json.load(sys.stdin).get('timestamp',''))" 2>/dev/null || echo "")
        if [ -n "$LAST_EVENT_TIME" ]; then
            info "    最近事件: $LAST_EVENT_TIME"
        fi

        # v1.7: Parallel ledger health check
        PARALLEL_EVENT_COUNT=$(grep -c 'parallel_phase_started\|worker_shard_delegated\|worker_shard_evidence_ready\|join_verification_result\|parallel_phase_gate_result' .phase_control/run_ledger.jsonl 2>/dev/null || echo "0")
        if [ "$PARALLEL_EVENT_COUNT" -gt 0 ]; then
            info "  Parallel events: $PARALLEL_EVENT_COUNT"
            # Check for dangling parallel phases (started but no gate result)
            python3 -c "
import json, sys
from collections import defaultdict

events = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                events.append(json.loads(line))
            except:
                pass

started_phases = set()
completed_phases = set()
for e in events:
    data = e.get('data', {}) if isinstance(e.get('data', {}), dict) else {}
    event = e.get('event', data.get('event', ''))
    phase_id = data.get('phase_id', e.get('phase_id', ''))
    if event == 'parallel_phase_started' and phase_id:
        started_phases.add(phase_id)
    elif event == 'parallel_phase_gate_result' and phase_id:
        completed_phases.add(phase_id)

dangling = started_phases - completed_phases
if dangling:
    print(f'WARN:dangling parallel phases (started but no gate result): {sorted(dangling)}')
else:
    print('OK:all parallel phases have gate results')
" .phase_control/run_ledger.jsonl 2>/dev/null | while IFS= read -r result; do
                if [[ "$result" == WARN:* ]]; then
                    warn "    ${result#WARN:}"
                    WARN_COUNT=$((WARN_COUNT + 1))
                elif [[ "$result" == OK:* ]]; then
                    success "    ${result#OK:}"
                    PASS_COUNT=$((PASS_COUNT + 1))
                fi
                TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
            done
        fi
    else
        warn "  run_ledger.jsonl 不存在（运行时生成）"
        WARN_COUNT=$((WARN_COUNT + 1))
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    fi
fi
echo ""

# ============================================================
# 6. 总结
# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "诊断完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "总检查项: $TOTAL_CHECKS"
echo "通过: $PASS_COUNT"
echo "失败: $FAIL_COUNT"
echo "警告: $WARN_COUNT"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    error "发现 $FAIL_COUNT 个错误，TAF legacy hmte runtime 可能无法正常运行"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "建议修复措施："
    echo "  - 如果 git repo 不存在: git init"
    echo "  - 如果 .phase_control 不存在: bash scripts/hmte-init.sh"
    echo "  - 如果脚本缺失: 检查项目完整性"
    echo ""
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "发现 $WARN_COUNT 个警告，TAF legacy hmte runtime 可以运行但可能有功能受限"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "所有检查通过！TAF legacy hmte 环境健康"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
fi
