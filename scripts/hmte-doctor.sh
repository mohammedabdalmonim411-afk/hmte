#!/usr/bin/env bash
# hmte-doctor.sh - HTE 轻量自检（只诊断，不修复）
#
# 检查项：
#   1. git repo 存在
#   2. bash 可用
#   3. python3 可用
#   4. HTE scripts 完整性
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
echo "🔍 HTE Doctor - 轻量自检"
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
# 4. 检查 HTE scripts 完整性
# ============================================================
info "检查 HTE scripts 完整性..."

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
    error "发现 $FAIL_COUNT 个错误，HTE 可能无法正常运行"
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
    warn "发现 $WARN_COUNT 个警告，HTE 可以运行但可能有功能受限"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "所有检查通过！HTE 环境健康"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
fi
